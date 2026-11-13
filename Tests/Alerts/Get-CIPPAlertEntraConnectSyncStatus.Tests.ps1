# Entra Connect sync alert: tenants without password hash sync (PTA/federated) have no password sync time; the
# directory sync time is still checked instead of the run failing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertEntraConnectSyncStatus.ps1')
}

Describe 'Get-CIPPAlertEntraConnectSyncStatus' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
    }

    It 'alerts on stale directory sync when there is no password sync time' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                onPremisesSyncEnabled              = $true
                onPremisesLastPasswordSyncDateTime = $null
                onPremisesLastSyncDateTime         = (Get-Date).ToUniversalTime().AddDays(-10)
            }
        }
        Get-CIPPAlertEntraConnectSyncStatus -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { $data.Cause -eq 'DirectorySync' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'stays quiet when directory sync is recent and there is no password sync time' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                onPremisesSyncEnabled              = $true
                onPremisesLastPasswordSyncDateTime = $null
                onPremisesLastSyncDateTime         = (Get-Date).ToUniversalTime().AddHours(-1)
            }
        }
        Get-CIPPAlertEntraConnectSyncStatus -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { -not $data }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
