BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPRoleAssignableGroupId.ps1')
}

Describe 'Get-CIPPRoleAssignableGroupId' {
    It 'returns the role-assignable groups and any group it could not read' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'plain'; status = 200; body = [pscustomobject]@{ id = 'plain'; isAssignableToRole = $null } }
                [pscustomobject]@{ id = 'admins'; status = 200; body = [pscustomobject]@{ id = 'admins'; isAssignableToRole = $true } }
                [pscustomobject]@{ id = 'denied'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'denied' } } }
            )
        }

        $Result = @(Get-CIPPRoleAssignableGroupId -GroupId 'plain', 'admins', 'denied', 'no-answer', 'plain' -TenantFilter 'contoso.com')

        $Result | Should -Be @('admins', 'denied', 'no-answer')
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'contoso.com' -and @($Requests).Count -eq 4 }
    }

    It 'makes no request when there are no groups' {
        Mock New-GraphBulkRequest { }
        Get-CIPPRoleAssignableGroupId -GroupId @() -TenantFilter 'contoso.com' | Should -BeNullOrEmpty
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }
}
