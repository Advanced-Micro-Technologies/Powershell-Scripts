# TeamsPersonal-Removal

Removes the consumer Microsoft Teams app (Teams personal / Teams free) from a
device — for every existing profile and for profiles created later — without
touching Teams for work or school.

### The problem

Windows 11 has shipped the consumer Teams client as an inbox Store app, package name
`MicrosoftTeams`. On a managed fleet it's clutter at best and a support problem
at worst: users sign in to it with their work account, wonder why their chats
and meetings aren't there, and open a ticket. It sits right next to the
work/school client, which is a different package (`MSTeams`), so the two are easy
to confuse.

Uninstalling it from Settings only removes it for the user who clicked. The
package exists in two places:

- **Installed per user.** Every profile that has signed in has its own
  registration.
- **Provisioned in the image.** Windows installs it into each new profile at
  first sign-in, so removing the per-user copies alone just means it comes back
  for the next new user.

### The approach

`Remove-TeamsPersonal.ps1` runs as SYSTEM and works through both locations, in
order:

1. **Per-user installs.** Enumerates `MicrosoftTeams` across all profiles with
   `Get-AppxPackage -AllUsers` and removes each with
   `Remove-AppxPackage -AllUsers`.
2. **Provisioned copy.** Enumerates `Get-AppxProvisionedPackage -Online` and
   deprovisions any match, so new profiles don't receive it.
3. **Verify.** Re-counts both. Any remaining artifact fails the script.

The provisioned list is collected into an array before anything is removed, so
the removal loop isn't iterating a pipeline that's changing underneath it.

Only the exact package name `MicrosoftTeams` is matched. The work/school client
(`MSTeams`) and classic Teams machine-wide installs are left alone.

### Usage

Deploy through **Intune → Devices → Scripts and remediations → Platform
scripts**, using these settings:

| Setting | Value |
| --- | --- |
| Run this script using the logged-on credentials | **No** |
| Enforce script signature check | **No** |
| Run script in 64-bit PowerShell host | **Yes** |

Logged-on credentials must be **No** — `-AllUsers` removal and deprovisioning
both need SYSTEM or local admin. The 64-bit host must be **Yes**: the DISM-backed
`*-AppxProvisionedPackage` cmdlets don't run from a 32-bit PowerShell on 64-bit
Windows.

To run it manually for testing, launch an elevated PowerShell session:

```powershell
.\Remove-TeamsPersonal.ps1
```

The script is safe to re-run. With nothing left to remove, it reports
`Remaining artifacts: 0` and exits `0`.

### Exit codes and logging

| Code | Meaning |
| --- | --- |
| `0` | No per-user or provisioned copies remain |
| `1` | Something was left behind, or the script threw — Intune will retry |

| Log | Contents |
| --- | --- |
| `C:\ProgramData\AMT\Logs\Remove-TeamsPersonal.log` | Full transcript, appended on each run |
| `C:\ProgramData\AMT\Logs\dism-teams.log` | DISM log from the deprovisioning step |

### Verify

From an elevated session, both of these should return nothing:

```powershell
Get-AppxPackage -Name MicrosoftTeams -AllUsers
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq 'MicrosoftTeams'
```

### Removal

There's nothing to tear down — the script leaves no task, file, or setting
behind other than its logs. If a user needs the consumer app back, they can
install **Microsoft Teams (free)** from the Microsoft Store.

### Requirements

- Windows 10 or 11
- Windows PowerShell 5.1, 64-bit
- SYSTEM or local administrator rights
- Intune platform script deployment (built for it; also runs from an elevated
  session for testing)

### Notes

**One-shot.** Intune platform scripts run once per device. If a feature update
or a user reinstall brings the package back, this won't catch it unless the
script content changes. For ongoing enforcement, run the same logic as a
remediation detection/remediation pair instead.

**Removal errors are quiet; the count isn't.** Individual remove calls use
`-ErrorAction SilentlyContinue` so one stubborn profile doesn't stop the rest.
The verify step is what decides success, and the transcript shows which package
was being removed when something didn't go.
