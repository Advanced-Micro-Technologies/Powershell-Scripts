# Set time zone to automatic
$ErrorActionPreference = 'Stop'
try {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' `
                     -Name 'Start' -Value 3 -PropertyType DWord -Force | Out-Null
    Start-Service tzautoupdate -ErrorAction SilentlyContinue
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}