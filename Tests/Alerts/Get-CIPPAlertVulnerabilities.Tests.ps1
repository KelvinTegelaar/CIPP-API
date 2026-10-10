# Pester tests for Get-CIPPAlertVulnerabilities.
# The alert folds the streamed TVM export (Get-DefenderTvmRaw -Stream) into one bucket per CVE instead
# of grouping every device x CVE record. Each bucket must report the earliest-seen record's details,
# the full record count and the unique device names, and CVE-less inventory rows must be ignored.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertVulnerabilities.ps1'

    function Get-DefenderTvmRaw { param($TenantId, [switch]$Stream) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev) }

    . $AlertPath

    function New-TvmRecord ($CveId, $DeviceName, $FirstSeen, $Cvss = 8.0) {
        [pscustomobject]@{
            cveId = $CveId; deviceName = $DeviceName; firstSeenTimestamp = [datetime]$FirstSeen
            lastSeenTimestamp = [datetime]'2026-09-01'; cvssScore = $Cvss; softwareName = "app-$FirstSeen"
            vulnerabilitySeverityLevel = 'High'; exploitabilityLevel = 'ExploitIsPublic'
        }
    }
}

Describe 'Get-CIPPAlertVulnerabilities' {
    BeforeEach {
        $script:Captured = $null
        Mock Write-AlertTrace { param($cmdletName, $tenantFilter, $data) $script:Captured = @($data) }
        Mock Write-LogMessage {}
        Mock Get-DefenderTvmRaw {
            New-TvmRecord 'CVE-B' 'PC1' '2026-03-01'
            New-TvmRecord 'CVE-A' 'PC1' '2026-05-01'
            New-TvmRecord 'CVE-A' 'PC2' '2026-02-01'
            New-TvmRecord 'CVE-A' 'PC1' '2026-04-01'
            New-TvmRecord $null 'PC3' '2026-01-01'
        }
    }

    It 'streams the TVM export' {
        Get-CIPPAlertVulnerabilities -InputValue @{ VulnerabilityAgeHours = 0 } -TenantFilter 'contoso.com'
        Should -Invoke Get-DefenderTvmRaw -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
    }

    It 'emits one row per CVE with the earliest record, record count and unique devices' {
        Get-CIPPAlertVulnerabilities -InputValue @{ VulnerabilityAgeHours = 0 } -TenantFilter 'contoso.com'
        $script:Captured.CVE | Should -Be @('CVE-A', 'CVE-B')
        $A = $script:Captured[0]
        $A.AffectedDeviceCount | Should -Be 3
        $A.AffectedDevices | Should -Be 'PC1, PC2'
        $A.SoftwareName | Should -Be 'app-2026-02-01'
    }

    It 'applies the CVSS threshold to the earliest record' {
        Mock Get-DefenderTvmRaw { New-TvmRecord 'CVE-A' 'PC1' '2026-02-01' 5.0; New-TvmRecord 'CVE-A' 'PC2' '2026-03-01' 9.5 }
        Get-CIPPAlertVulnerabilities -InputValue @{ CVSSSeverity = @{ value = 'high' } } -TenantFilter 'contoso.com'
        $script:Captured | Should -BeNullOrEmpty
    }
}
