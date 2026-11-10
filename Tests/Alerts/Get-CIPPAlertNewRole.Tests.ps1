# New role alert: service principals and groups added to a role alert too, but only once a baseline that tracks
# them exists, so the first run after an upgrade does not report every existing one as new.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($Table, $tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertNewRole.ps1')
}

Describe 'Get-CIPPAlertNewRole' {
    BeforeEach {
        Mock Get-CIPPTable { @{ TableName = 'DeltaCompare' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                displayName = 'Global Administrator'
                members     = @(
                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.user'; displayName = 'Alice'; userPrincipalName = 'alice@contoso.com' }
                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-new'; displayName = 'Evil App' }
                )
            }
        }
    }

    It 'compares by object id: a same-named newcomer alerts, a renamed existing member does not' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                displayName = 'Global Administrator'
                members     = @(
                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-old'; displayName = 'Renamed App' }
                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-new'; displayName = 'Evil App' }
                )
            }
        }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ delta = '[{"GroupName":"Global Administrator","Members":null,"OtherMembers":[{"id":"sp-old","name":"Evil App (servicePrincipal)"}]}]' } }
        Get-CIPPAlertNewRole -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 1 -and $data.User -eq 'Evil App (servicePrincipal)' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'alerts when a service principal is added to a role' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ delta = '[{"GroupName":"Global Administrator","Members":"alice@contoso.com","OtherMembers":[]}]' } }
        Get-CIPPAlertNewRole -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 1 -and $data.User -eq 'Evil App (servicePrincipal)' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'does not report existing service principals against a baseline that never tracked them' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ delta = '[{"GroupName":"Global Administrator","Members":"alice@contoso.com"}]' } }
        Get-CIPPAlertNewRole -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { -not $data }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
