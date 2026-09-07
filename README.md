# Powershell-Scripts

Windows automation and endpoint utility scripts.

Each project lives in its own folder with everything it needs, including its own
README carrying the full write-up. Scripts are written for Windows PowerShell
5.1 unless noted otherwise.

| Project | What it does |
| --- | --- |
| [WaveLink-EarlyStart](WaveLink-EarlyStart/) | Makes Elgato Wave Link 3 launch early at logon, hidden |
| [OpenVPNGUI-RunKeyRemoval](OpenVPNGUI-RunKeyRemoval/) | Strips the OpenVPN GUI autostart entry at every user logon |

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

## License

GPL-2.0. See [LICENSE.txt](LICENSE.txt).
