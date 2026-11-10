# Permanent active admin alert: an empty stored baseline ('[]') is a baseline, not a first run, so the first
# permanent admin in a fully PIM-eligible tenant alerts.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPPIMRoleAssignments { param($TenantFilter) }
    function Get-CIPPTable { param($Table, $tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertPermanentActiveAdminAssigned.ps1')
}

Describe 'Get-CIPPAlertPermanentActiveAdminAssigned' {
    BeforeEach {
        Mock Get-CIPPTable { @{ TableName = 'DeltaCompare' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
        Mock Get-CIPPPIMRoleAssignments {
            [PSCustomObject]@{
                AssignmentType             = 'Permanent'
                MemberType                 = 'User'
                IsPrivilegedRole           = $true
                PrincipalId                = 'p1'
                RoleDefinitionId           = 'r1'
                DirectoryScopeId           = '/'
                PrincipalDisplayName       = 'Eve'
                PrincipalUserPrincipalName = 'eve@contoso.com'
                PrincipalType              = 'User'
                RoleDisplayName            = 'Global Administrator'
                Scope                      = 'Directory'
            }
        }
    }

    It 'alerts on the first permanent admin when the stored baseline is empty' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ delta = '[]' } }
        Get-CIPPAlertPermanentActiveAdminAssigned -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 1 -and $data.Role -eq 'Global Administrator' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'only seeds the baseline when no row is stored yet' {
        Mock Get-CIPPAzDataTableEntity { }
        Get-CIPPAlertPermanentActiveAdminAssigned -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Write-AlertTrace -Times 0 -Exactly
    }
}
