# Device compliance alert: tenants without an Intune plan are skipped up front instead of logging a
# Graph error on every run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertDeviceCompliance.ps1')
}

Describe 'Get-CIPPAlertDeviceCompliance' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {}
    }

    It 'skips tenants without an Intune license without calling Graph or logging an error' {
        Mock Test-CIPPStandardLicense { $false }
        Mock New-GraphGetRequest { throw 'There is no subscription for this service available' }

        Get-CIPPAlertDeviceCompliance -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Test-CIPPStandardLicense -Times 1 -Exactly -ParameterFilter { $Preset -eq 'Intune' }
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }

    It 'queries managed devices for a licensed tenant' {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphGetRequest { @() }

        Get-CIPPAlertDeviceCompliance -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
