# LSA-Protection

Checks whether LSA Protection (`RunAsPPL`) is configured, and turns it on if it
isn't — so LSASS starts as a protected process and credential-dumping tools
can't read its memory.

### The problem

The Local Security Authority Subsystem Service (`lsass.exe`) holds credential
material for signed-in users. Tools like Mimikatz work by opening LSASS and
reading that memory. LSA Protection runs LSASS as a Protected Process Light
(PPL), which blocks non-protected processes from reading its memory or injecting
code into it.

It's controlled by one registry value:

```
HKLM\SYSTEM\CurrentControlSet\Control\Lsa
    RunAsPPL
```

| Value | Meaning |
| --- | --- |
| `1` | Enabled **with** UEFI lock — the setting is also stored in firmware (Microsoft's recommendation) |
| `2` | Enabled **without** UEFI lock — registry only (Windows 11 22H2 and later) |

Windows 11 22H2+ enables it by default, without UEFI lock, but only on clean
installs that are enterprise-joined and HVCI-capable. Upgraded machines,
non-HVCI hardware, and everything older are left unprotected.

Two things make a plain registry push hard to trust on its own: the change does
nothing until a reboot, and a third-party LSA plug-in or driver that isn't
signed for protected-process loading can be silently blocked.

### The approach

`Set-LSAProtection.ps1` runs detect → fix → verify, and logs enough context to
triage a device that doesn't end up protected.

1. **Detect.** Reads `RunAsPPL` and checks the LSASS runtime state by looking for
   Wininit Event ID 12 (*LSASS.exe was started as a protected process*) since the
   last boot. If the value is already correct, it logs, warns if a reboot is
   still pending, and exits without changing anything.
2. **Pre-flight.** Before writing, logs whether Secure Boot is on (without it,
   `RunAsPPL=1` applies but the UEFI lock can't be set), and lists up to five
   CodeIntegrity 3033/3063 events from the last 30 days — the usual sign that an
   LSA plug-in or driver will be blocked from loading.
3. **Fix.** Writes `RunAsPPL` as `REG_DWORD`, creating the key if needed.
   Optionally writes the companion `RunAsPPLBoot` value on build 22621+.
4. **Verify.** Reads the value back and fails if it doesn't match.

Two settings sit at the top of the script:

| Setting | Default | Purpose |
| --- | --- | --- |
| `$DesiredValue` | `1` | `1` = with UEFI lock, `2` = without |
| `$IncludeRunAsPPLBoot` | `$false` | Also write `RunAsPPLBoot` on build 22621+, matching the OS default-enablement pattern |

### Usage

Deploy through **Intune → Devices → Scripts and remediations → Platform
scripts**, using these settings:

| Setting | Value |
| --- | --- |
| Run this script using the logged-on credentials | **No** |
| Enforce script signature check | **No** |
| Run script in 64-bit PowerShell host | **Yes** |

To run it manually for testing, launch an elevated PowerShell session:

```powershell
.\Set-LSAProtection.ps1
```

**A reboot is required** before LSASS actually starts protected. The script
doesn't force one.

### Exit codes and logging

| Code | Meaning |
| --- | --- |
| `0` | Already compliant, or remediated successfully |
| `1` | Failure — Intune will retry up to three times |

The log is written to `C:\ProgramData\AMT\Logs\LSA-Protection.log` and also
echoed to output, so it appears in `IntuneManagementExtension.log`.

### Verify

Registry value:

```powershell
Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL
```

Runtime state, after a reboot — look for Event ID 12 from Wininit:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'System'; ProviderName = 'Microsoft-Windows-Wininit'; Id = 12
} -MaxEvents 1
```

*LSASS.exe was started as a protected process with level: 4* means it worked.

### Removal

How you back this out depends on which value was deployed.

**`RunAsPPL=2` (no UEFI lock):** set `RunAsPPL` to `0` or delete it, then reboot.

**`RunAsPPL=1` (UEFI lock, the default here):** changing the registry is not
enough. The setting lives in a UEFI variable that registry and policy changes don't
override.
Set `RunAsPPL` to `0`, then remove the UEFI variable with Microsoft's
[LSA Protected Process Opt-out tool](https://www.microsoft.com/download/details.aspx?id=40897)
(`LsaPplConfig.efi`), then reboot. Plan on hands-on access to the device.

See Microsoft's
[Configure added LSA protection](https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection)
for the full procedure.

### Requirements

- Windows 10 / Windows Server 2016 or later (`RunAsPPL=2` requires Windows 11
  22H2 or later)
- Secure Boot, for the UEFI lock to take effect
- Windows PowerShell 5.1
- SYSTEM or local administrator rights
- Intune platform script deployment (built for it; also runs from an elevated
  session for testing)

### Notes

**Check for blocked plug-ins before you roll wide.** Smart card middleware,
some password filters, and older security agents load into LSASS. If they
aren't signed for protected-process loading, they're blocked once protection is
on. The CodeIntegrity 3033/3063 events the script logs are the early warning;
audit mode for LSA protection is on by default from Windows 11 22H2, so those
events may already exist before you deploy.

**Choose the UEFI lock deliberately.** Value `1` is harder to undo, which is
the point — malware with admin rights can't just flip the registry. It also
means a misbehaving LSA plug-in can't be fixed remotely by turning protection
off. If you aren't sure about plug-in compatibility, deploy `2` first.

**Already managed by policy?** If the Settings Catalog *Local Security
Authority → Configure LSASS to run as a protected process* policy is assigned,
use one mechanism, not both, so the two can't disagree.
