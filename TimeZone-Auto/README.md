# TimeZone-Auto

Turns on **Set time zone automatically** at the device level, so laptops pick
up the correct time zone when they travel instead of keeping whatever the image
was built with.

### The problem

The **Settings → Time & language → Date & time → Set time zone automatically**
toggle is backed by the Auto Time Zone Updater service, `tzautoupdate`. On many
images and Autopilot builds that service is disabled, which greys out or turns
off the toggle — and a device provisioned in one time zone stays there.

The service's startup type is stored in:

```
HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate
    Start
```

| Value | Startup type | Toggle |
| --- | --- | --- |
| `3` | Manual (trigger start) | On |
| `4` | Disabled | Off |

### The approach

`Set-TimeZoneAuto.ps1` writes `Start = 3` and starts the service. That's the
same state Windows uses when a user turns the toggle on by hand.

### Usage

Deploy through **Intune → Devices → Scripts and remediations → Platform
scripts**, using these settings:

| Setting | Value |
| --- | --- |
| Run this script using the logged-on credentials | **No** |
| Enforce script signature check | **No** |
| Run script in 64-bit PowerShell host | **Yes** |

Logged-on credentials must be **No** — the script writes under `HKLM\SYSTEM`.

To run it manually for testing, launch an elevated PowerShell session:

```powershell
.\Set-TimeZoneAuto.ps1
```

The script is idempotent.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Registry value written |
| `1` | Registry write failed — Intune will retry |

There's no log file; any error message appears in
`IntuneManagementExtension.log`.

### Verify

```powershell
Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start
Get-Service tzautoupdate
```

`Start` should read `3`, and **Set time zone automatically** should show as on
in Settings.

### Removal

To turn the toggle back off, set the startup type to Disabled from an elevated
session:

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -Value 4
Stop-Service tzautoupdate -ErrorAction SilentlyContinue
```

### Requirements

- Windows 10 or 11
- Windows PowerShell 5.1
- SYSTEM or local administrator rights
- Intune platform script deployment (built for it; also runs from an elevated
  session for testing)

### Notes

**Location services must be on.** `tzautoupdate` works out the time zone from
the device's location. If location services are off — by the user, in the
privacy settings, or by policy — the toggle can show as on and the time zone
still won't change. Make sure your location privacy policy allows it.

**Success means the setting is in place, not that the time zone changed.** A
failure to start the service is ignored — `tzautoupdate` is trigger-started, so
Windows will start it on its own when needed. Only the registry write affects
the exit code.
