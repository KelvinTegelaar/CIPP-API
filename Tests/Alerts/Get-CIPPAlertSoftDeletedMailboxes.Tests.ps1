# Soft-deleted mailboxes alert: tenants without an Exchange plan are skipped up front instead of
# logging an EXO "no subscription" error on every run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertSoftDeletedMailboxes.ps1')
}

Describe 'Get-CIPPAlertSoftDeletedMailboxes' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {}
    }

    It 'skips tenants without an Exchange license without calling EXO or logging an error' {
        Mock Test-CIPPStandardLicense { $false }
        Mock New-ExoRequest { throw 'There is no subscription for this service available' }

        Get-CIPPAlertSoftDeletedMailboxes -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Test-CIPPStandardLicense -Times 1 -Exactly -ParameterFilter { $Preset -eq 'Exchange' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }

    It 'queries EXO for a licensed tenant' {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-ExoRequest { @() }

        Get-CIPPAlertSoftDeletedMailboxes -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-ExoRequest -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
