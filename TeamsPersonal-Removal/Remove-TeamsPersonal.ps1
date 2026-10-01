$ErrorActionPreference = 'Stop'
$Name = 'MicrosoftTeams'
$Log  = "$env:ProgramData\AMT\Logs\Remove-TeamsPersonal.log"
New-Item -ItemType Directory -Path (Split-Path $Log) -Force | Out-Null
Start-Transcript -Path $Log -Append

try {
    # 1. Per-user installs, all profiles
    foreach ($p in @(Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue)) {
        Write-Output "Removing user package $($p.PackageFullName)"
        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }

    # 2. Provisioned copy - enumerate FIRST, no -AllUsers
    $prov = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $Name })
    foreach ($p in $prov) {
        Write-Output "Deprovisioning $($p.PackageName)"
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName `
            -LogPath "$env:ProgramData\AMT\Logs\dism-teams.log" -LogLevel 3 -ErrorAction SilentlyContinue
    }

    # 3. Verify
    $left = @(Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue).Count +
            @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $Name }).Count
    Write-Output "Remaining artifacts: $left"
    Stop-Transcript
    if ($left -gt 0) { exit 1 } else { exit 0 }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}