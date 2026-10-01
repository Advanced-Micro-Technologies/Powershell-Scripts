<#
.SYNOPSIS
    Verifies LSA Protection (RunAsPPL) and configures it if not set correctly.

.DESCRIPTION
    Intune platform script (Devices > Scripts). Runs once per device as SYSTEM.

    Checks HKLM\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL. If the value is
    already correct, the script logs and exits without changing anything. If it
    is missing or wrong, the script writes the correct REG_DWORD and verifies
    the write.

    Value meanings:
        1 = Enabled with UEFI lock   (Microsoft's recommendation)
        2 = Enabled without UEFI lock

    On Windows 11 22H2 / Server 2022 and later, Windows also maintains a
    companion value named RunAsPPLBoot. Set $IncludeRunAsPPLBoot to $true to
    write it on those builds, matching the OS default enablement pattern.

    A reboot is required before LSASS actually starts protected. The script
    reports the current runtime state via Wininit Event ID 12 so a compliant
    registry value on an un-rebooted machine is visible as such.

    Exit codes:
        0 = compliant or successfully remediated
        1 = failure (Intune will retry up to 3 times)

.NOTES
    Author  : Advanced Micro Technologies, LLC
    Config  : Run this script using the logged on credentials : No
              Enforce script signature check                  : No
              Run script in 64 bit PowerShell Host            : Yes
    Log     : C:\ProgramData\AMT\Logs\LSA-Protection.log
              (also captured in IntuneManagementExtension.log)
#>

# ----- Settings ---------------------------------------------------------------

$DesiredValue        = 1        # 1 = UEFI lock, 2 = no UEFI lock
$IncludeRunAsPPLBoot = $false   # $true to also write RunAsPPLBoot on build 22621+

# ------------------------------------------------------------------------------

$RegPath   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$ValueName = 'RunAsPPL'
$LogDir    = 'C:\ProgramData\AMT\Logs'
$LogFile   = Join-Path $LogDir 'LSA-Protection.log'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Output $line
    try {
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -ErrorAction Stop
    } catch { }
}

function Get-LsassRuntimeState {
    # Wininit Event ID 12: "LSASS.exe was started as a protected process with level: 4"
    try {
        $evt = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Wininit'
            Id           = 12
        } -MaxEvents 1 -ErrorAction Stop

        $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ($evt.TimeCreated -ge $bootTime.AddMinutes(-5)) { return 'Protected (this boot)' }
        return 'Not protected (pending reboot)'
    }
    catch {
        return 'Not protected (pending reboot)'
    }
}

Write-Log "----- LSA Protection check started on $env:COMPUTERNAME -----"

try {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("OS: {0} (build {1})" -f $os.Caption, $os.BuildNumber)

    # --- Detect ---------------------------------------------------------------

    $current = $null
    try { $current = Get-ItemPropertyValue -Path $RegPath -Name $ValueName -ErrorAction Stop } catch { }

    $runtime = Get-LsassRuntimeState
    Write-Log ("Current RunAsPPL: {0} | LSASS runtime state: {1}" -f `
        $(if ($null -eq $current) { '<not set>' } else { $current }), $runtime)

    if ($null -ne $current -and [int]$current -eq $DesiredValue) {
        Write-Log "Already compliant. No change made."
        if ($runtime -notlike 'Protected*') {
            Write-Log "Registry is correct but LSASS is not yet protected. Device needs a reboot." 'WARN'
        }
        Write-Log "----- Completed: compliant -----"
        exit 0
    }

    # --- Pre-flight context (non-blocking, logged for triage) -----------------

    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
        Write-Log "Secure Boot enabled: $secureBoot"
        if ($DesiredValue -eq 1 -and -not $secureBoot) {
            Write-Log "Secure Boot is off. RunAsPPL=1 will apply, but the UEFI lock cannot be enforced." 'WARN'
        }
    }
    catch {
        Write-Log "Secure Boot state could not be determined (legacy BIOS or unsupported platform)." 'WARN'
    }

    # CodeIntegrity 3033/3063 indicate a binary was blocked from loading into a
    # protected process - the usual cause of LSA protection silently failing.
    try {
        $ciBlocks = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-CodeIntegrity/Operational'
            Id        = 3033, 3063
            StartTime = (Get-Date).AddDays(-30)
        } -ErrorAction Stop

        Write-Log ("Found {0} CodeIntegrity block event(s) in the last 30 days. Review for incompatible LSA plugins/drivers." -f $ciBlocks.Count) 'WARN'
        foreach ($e in ($ciBlocks | Select-Object -First 5)) {
            Write-Log ("  CI Event {0} @ {1}: {2}" -f $e.Id, $e.TimeCreated, ($e.Message -split "`r?`n")[0]) 'WARN'
        }
    }
    catch {
        Write-Log "No CodeIntegrity block events (3033/3063) found in the last 30 days."
    }

    # --- Fix ------------------------------------------------------------------

    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force -ErrorAction Stop | Out-Null
        Write-Log "Created missing key: $RegPath" 'WARN'
    }

    New-ItemProperty -Path $RegPath -Name $ValueName -Value $DesiredValue `
        -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    if ($IncludeRunAsPPLBoot -and [int]$os.BuildNumber -ge 22621) {
        New-ItemProperty -Path $RegPath -Name 'RunAsPPLBoot' -Value $DesiredValue `
            -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Log "RunAsPPLBoot set to $DesiredValue (build $($os.BuildNumber))."
    }

    # --- Verify ---------------------------------------------------------------

    $after = Get-ItemPropertyValue -Path $RegPath -Name $ValueName -ErrorAction Stop
    if ([int]$after -ne $DesiredValue) {
        Write-Log "Verification failed. RunAsPPL reads $after after write." 'ERROR'
        exit 1
    }

    Write-Log "RunAsPPL set to $after. Reboot required for LSASS to start as a protected process."
    Write-Log "Post-reboot validation: System log, Microsoft-Windows-Wininit, Event ID 12."
    Write-Log "----- Completed: remediated -----"
    exit 0
}
catch {
    Write-Log "Failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
