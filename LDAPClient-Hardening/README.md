# LDAPClient-Hardening

Requires the Windows LDAP client to sign and encrypt its LDAP traffic, closing
the security recommendation *"Encrypt LDAP client traffic to protect sensitive
data in transit"*.

### The problem

By default, the Windows LDAP client negotiates signing and encryption with the
server but will fall back to sending traffic in the clear if the other side
doesn't insist. That leaves directory queries and binds open to interception
and tampering on the wire.

Two client-side settings control this, both under:

```
HKLM\SYSTEM\CurrentControlSet\Services\ldap
```

| Value | Group Policy name | Meaning of `2` |
| --- | --- | --- |
| `LDAPClientIntegrity` | Network security: LDAP client signing requirements | Require signing |
| `LDAPClientConfidentiality` | Network security: LDAP client encryption requirements | Require encryption |

`LDAPClientConfidentiality` is new — it only exists on build 26100 and later
(Windows 11 24H2 / Windows Server 2025).

### The approach

`Set-LDAPClientHardening.ps1` writes both values as `REG_DWORD 2`, reads them
back, and reports the result. On builds below 26100 it skips entirely and exits
`0`, since the encryption setting isn't supported there.

This is client-side only. It changes what the device demands when it talks to
an LDAP server; it doesn't change domain controller policy.

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
.\Set-LDAPClientHardening.ps1
```

The script is idempotent — it writes the same values every run.

### Output and exit codes

| Output | Exit | Meaning |
| --- | --- | --- |
| `OK: Confidentiality=2 Integrity=2` | `0` | Both values set and verified |
| `SKIP: Build <n> predates ...` | `0` | Build below 26100; nothing written |
| `FAIL: ...` | `1` | Write or read-back failed — Intune will retry |

Output lands in the Intune Management Extension log
(`IntuneManagementExtension.log`); the script writes no log file of its own.

### Verify

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\ldap' |
    Select-Object LDAPClientConfidentiality, LDAPClientIntegrity
```

Both should read `2`.

### Removal

To return to the negotiate-but-don't-require behavior, set both values back to
`1` from an elevated session:

```powershell
$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\ldap'
Set-ItemProperty -Path $p -Name LDAPClientConfidentiality -Value 1
Set-ItemProperty -Path $p -Name LDAPClientIntegrity -Value 1
```

### Requirements

- Windows 11 24H2 / Windows Server 2025 (build 26100) or later — older builds
  are skipped
- Windows PowerShell 5.1
- SYSTEM or local administrator rights
- Intune platform script deployment (built for it; also runs from an elevated
  session for testing)

### Notes

**Test before broad rollout.** Requiring signing and encryption is safe against
Active Directory domain controllers, which support both. Anything on the device
that binds to a *non-AD* LDAP server over plain port 389 — a line-of-business
app, a scanner or MFP address book, a third-party directory — may fail once the
client refuses unsigned, unencrypted sessions. Pilot on a small group first.

**Older builds get nothing, including signing.** `LDAPClientIntegrity` is
supported on far older Windows releases, but the build check skips both values
together. If you want signing required on pre-24H2 devices too, that needs a
separate deployment.

**One-shot.** Intune platform scripts run once per device. A machine that
reports `SKIP` today won't be revisited after it upgrades to 24H2 unless the
script content changes, or the settings are delivered through a remediation or
the Settings Catalog instead.
