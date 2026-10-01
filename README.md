# Powershell-Scripts

Windows automation and endpoint utility scripts.

Each project lives in its own folder with everything it needs, including its own
README carrying the full write-up. Scripts are written for Windows PowerShell
5.1 unless noted otherwise.

| Project | What it does |
| --- | --- |
| [WaveLink-EarlyStart](WaveLink-EarlyStart/) | Makes Elgato Wave Link 3 launch early at logon, hidden |
| [OpenVPNGUI-RunKeyRemoval](OpenVPNGUI-RunKeyRemoval/) | Strips the OpenVPN GUI autostart entry at every user logon |
| [TeamsPersonal-Removal](TeamsPersonal-Removal/) | Removes consumer Teams for all users and deprovisions it from the image |
| [LDAPClient-Hardening](LDAPClient-Hardening/) | Requires LDAP client signing and encryption on Windows 11 24H2+ |
| [LSA-Protection](LSA-Protection/) | Checks and enables LSA Protection (`RunAsPPL`) with triage logging |
| [TimeZone-Auto](TimeZone-Auto/) | Turns on "Set time zone automatically" device-wide |

## WaveLink-EarlyStart

Wave Link 3 is an MSIX-packaged app, so Windows runs its autostart last in the
logon chain, and its "start minimized to tray" behavior only happens when
Windows launches it through the registered startup task. The deployer disables
that native startup task, registers a logon-triggered scheduled task that fires
early instead, and hides the window manually once the app is up. It runs
unelevated, discovers the package family name and startup task GUID at runtime,
and `-Remove` puts everything back.

Full write-up, requirements, and teardown:
[WaveLink-EarlyStart/README.md](WaveLink-EarlyStart/README.md)

## OpenVPNGUI-RunKeyRemoval

OpenVPN GUI autostarts from the per-user Run key, which makes a one-shot cleanup
unreliable on a managed fleet: the value is per-profile, client upgrades and the
GUI's own toggle recreate it, and an Intune platform script only runs once. This
deploys once in SYSTEM context and leaves behind a logon-triggered scheduled
task, registered against `BUILTIN\Users`, that strips the value in the context
of whoever just signed in. Manual launch still works; only the autostart goes
away.

Full write-up, Intune settings, verification, and teardown:
[OpenVPNGUI-RunKeyRemoval/README.md](OpenVPNGUI-RunKeyRemoval/README.md)

## TeamsPersonal-Removal

The consumer Teams app (`MicrosoftTeams`) is installed per profile and also
provisioned in the image, so uninstalling it for one user just means it comes
back for the next. This Intune platform script runs as SYSTEM, removes every
per-user registration, deprovisions the image copy so new profiles don't get it,
then verifies both are gone and fails if anything is left, so Intune retries.
Teams for work or school (`MSTeams`) is not touched.

Full write-up, Intune settings, logs, and verification:
[TeamsPersonal-Removal/README.md](TeamsPersonal-Removal/README.md)

## LDAPClient-Hardening

An Intune platform script that sets `LDAPClientIntegrity` and
`LDAPClientConfidentiality` to `2`, so the Windows LDAP client requires signing
and encryption instead of falling back to cleartext. Written to close the *"Encrypt LDAP client traffic to protect
sensitive data in transit"* recommendation. The encryption setting only exists
on build 26100 and later, so older builds are skipped. Test against any non-AD
LDAP servers before rolling it wide.

Full write-up, Intune settings, compatibility notes, and rollback:
[LDAPClient-Hardening/README.md](LDAPClient-Hardening/README.md)

## LSA-Protection

Runs LSASS as a protected process so credential-dumping tools can't read its
memory. The Intune platform script checks `RunAsPPL` and the live LSASS state first and leaves
compliant machines alone. Otherwise it logs Secure Boot status and any recent
CodeIntegrity block events, writes the value (UEFI-locked by default), and
verifies it, exiting non-zero on failure so Intune retries. Takes effect after a
reboot. Backing out a UEFI-locked setting
needs Microsoft's opt-out tool, not just a registry change.

Full write-up, Intune settings, verification, and removal:
[LSA-Protection/README.md](LSA-Protection/README.md)

## TimeZone-Auto

An Intune platform script that sets the `tzautoupdate` service to manual start
and starts it, which is what turns on **Set time zone automatically** in
Settings. Useful on images and
Autopilot builds where the service ships disabled and devices stay stuck in the
time zone they were provisioned in. Needs location services enabled to actually
change the time zone.

Full write-up, Intune settings, verification, and rollback:
[TimeZone-Auto/README.md](TimeZone-Auto/README.md)

## License

GPL-2.0. See [LICENSE.txt](LICENSE.txt).
