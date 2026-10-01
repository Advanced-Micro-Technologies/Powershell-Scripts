<#
    Enforces LDAP client encryption and signing.
    Remediates: "Encrypt LDAP client traffic to protect sensitive data in transit"

        HKLM\SYSTEM\CurrentControlSet\Services\ldap
            LDAPClientConfidentiality = 2   (Require encryption)
            LDAPClientIntegrity       = 2   (Require signing)

    Client-side only. LDAPClientConfidentiality requires build 26100+
    (Windows 11 24H2 / Server 2025).

    Intune platform script settings:
        Logged on credentials: No | Signature check: No | 64-bit host: Yes
#>

$Path  = 'HKLM:\SYSTEM\CurrentControlSet\Services\ldap'
$Build = [Environment]::OSVersion.Version.Build

if ($Build -lt 26100) {
    Write-Output "SKIP: Build $Build predates LDAPClientConfidentiality support."
    exit 0
}

try {
    foreach ($Name in 'LDAPClientConfidentiality', 'LDAPClientIntegrity') {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
    }

    $v = Get-ItemProperty -Path $Path -ErrorAction Stop

    if ($v.LDAPClientConfidentiality -eq 2 -and $v.LDAPClientIntegrity -eq 2) {
        Write-Output "OK: Confidentiality=$($v.LDAPClientConfidentiality) Integrity=$($v.LDAPClientIntegrity)"
        exit 0
    }

    Write-Output "FAIL: Confidentiality=$($v.LDAPClientConfidentiality) Integrity=$($v.LDAPClientIntegrity)"
    exit 1
}
catch {
    Write-Output "FAIL: $($_.Exception.Message)"
    exit 1
}
