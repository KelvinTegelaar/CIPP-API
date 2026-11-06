# New risky users alert: a tenant without Entra ID P2 is skipped quietly through the shared licence gate, the same way
# every other licensed alert skips, with no log line and no table or Graph read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CIPPTable { param($Table, $tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertNewRiskyUsers.ps1')
}

Describe 'Get-CIPPAlertNewRiskyUsers' {
    BeforeEach {
        Mock Get-CIPPTable { @{ TableName = 'DeltaCompare' } }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock New-GraphGetRequest { @() }
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
    }

    It 'skips a tenant without P2 quietly, before any table or Graph read' {
        Mock Test-CIPPStandardLicense { $false }
        Get-CIPPAlertNewRiskyUsers -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Test-CIPPStandardLicense -Times 1 -Exactly -ParameterFilter { $Preset -eq 'EntraP2' -and $SkipLog }
        Should -Invoke Get-CIPPTable -Times 0 -Exactly
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'checks a P2 tenant' {
        Mock Test-CIPPStandardLicense { $true }
        Get-CIPPAlertNewRiskyUsers -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }
}
