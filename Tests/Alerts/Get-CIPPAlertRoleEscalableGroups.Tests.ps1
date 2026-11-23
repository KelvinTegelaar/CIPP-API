BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertRoleEscalableGroups.ps1')
}

Describe 'Get-CIPPAlertRoleEscalableGroups' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
        Mock Get-CippException { [PSCustomObject]@{ NormalizedError = 'failed' } }
        Mock New-GraphGetRequest { @() }
        Mock New-GraphGetRequest {
            [PSCustomObject]@{ id = 'g1'; displayName = 'Helpdesk'; isAssignableToRole = $false }
        } -ParameterFilter { $uri -match 'beta/groups\?' }
        Mock New-GraphGetRequest {
            [PSCustomObject]@{ id = 'r1'; displayName = 'Global Administrator' }
        } -ParameterFilter { $uri -match 'roleDefinitions\?' }
        Mock New-GraphGetRequest {
            if ($uri -match 'appScopeId') { throw "Could not find a property named 'appScopeId' on type 'Microsoft.DirectoryServices.RoleAssignment'." }
            [PSCustomObject]@{ id = 'a1'; principalId = 'g1'; roleDefinitionId = 'r1'; directoryScopeId = '/' }
        } -ParameterFilter { $uri -match 'roleAssignments\?' }
    }

    It 'reports a group holding a role without being role-assignable' {
        Get-CIPPAlertRoleEscalableGroups -TenantFilter 'contoso.com'

        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter {
            @($data).Count -eq 1 -and $data[0].PathType -eq 'Direct' -and $data[0].GroupId -eq 'g1' -and $data[0].RoleName -eq 'Global Administrator'
        }
    }
}
