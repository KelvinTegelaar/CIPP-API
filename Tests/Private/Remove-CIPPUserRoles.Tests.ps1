# Pester tests for Remove-CIPPUserRoles.
#
# The "remove all admin roles" step of offboarding. It reads every directory role assignment the
# user holds and removes each one through the right path: the PIM write helper on a PIM-licensed
# tenant, a direct delete of the unified role assignment elsewhere.
#
# What matters here is what it refuses and how it reports: a role inherited through a
# role-assignable group is left to the group removal step, the last Global Administrator is never
# removed, and a failure on one role must not stop the others. The progress view marks the step
# failed from lines starting with 'Failed', so that wording is part of the contract.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPUserRoles.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Remove-CIPPUserRoles.ps1 under Modules/' }

    function Get-CIPPPIMRoleAssignments { param($TenantFilter, $PrincipalId, $RoleDefinitionId) }
    function Invoke-CIPPPIMAssignmentAction { param($TenantFilter, $Action, $PrincipalId, $RoleDefinitionId, $DirectoryScopeId, $AssignmentType, $Justification, $Headers, $APIName) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }

    . $FunctionPath

    $script:GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'

    function New-Row {
        param(
            [string]$RoleId,
            [string]$RoleName,
            [string]$AssignmentType = 'Permanent',
            [string]$MemberType = 'Direct',
            [string]$ScopeId = '/',
            [bool]$PIMCapable = $true,
            [string]$RoleAssignmentId,
            [string]$PrincipalId = 'user-guid'
        )
        [pscustomobject]@{
            PrincipalId      = $PrincipalId
            RoleDefinitionId = $RoleId
            RoleDisplayName  = $RoleName
            AssignmentType   = $AssignmentType
            MemberType       = $MemberType
            DirectoryScopeId = $ScopeId
            PIMCapable       = $PIMCapable
            RoleAssignmentId = $RoleAssignmentId
        }
    }

    # Data for the mocks lives in script scope: the mock scriptblocks run after these helpers return.
    function Set-UserRows { param([object[]]$Rows) $script:UserRows = @($Rows) }
    function Set-GlobalAdminRows { param([object[]]$Rows) $script:GlobalAdminRows = @($Rows) }
}

Describe 'Remove-CIPPUserRoles' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Invoke-CIPPPIMAssignmentAction -MockWith { [pscustomobject]@{ state = 'success' } }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'user-guid' } }
        Set-UserRows -Rows @()
        Set-GlobalAdminRows -Rows @()

        Mock -CommandName Get-CIPPPIMRoleAssignments -MockWith { $script:UserRows } -ParameterFilter { $PrincipalId }
        Mock -CommandName Get-CIPPPIMRoleAssignments -MockWith { $script:GlobalAdminRows } -ParameterFilter { -not $PrincipalId }
    }

    It 'reports when the user holds no roles and changes nothing' {
        $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

        $Result | Should -Be 'sseck@contoso.com has no directory role assignments.'
        Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'resolves the object id from the UPN when none is given' {
        Set-UserRows -Rows @(New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator')

        $null = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*users/sseck%40contoso.com?$select=id' }
        Should -Invoke Get-CIPPPIMRoleAssignments -Times 1 -Exactly -ParameterFilter { $PrincipalId -eq 'user-guid' }
    }

    Context 'PIM-licensed tenant' {
        It 'removes each assignment through the PIM write helper, eligibilities last' {
            Set-UserRows -Rows @(
                (New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator' -AssignmentType 'Eligible')
                (New-Row -RoleId 'role-2' -RoleName 'User Administrator' -AssignmentType 'Permanent')
                (New-Row -RoleId 'role-3' -RoleName 'Groups Administrator' -AssignmentType 'ActivatedFromEligible' -ScopeId '/administrativeUnits/au-1')
            )
            $script:CallOrder = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Invoke-CIPPPIMAssignmentAction -MockWith { $script:CallOrder.Add($AssignmentType); [pscustomobject]@{ state = 'success' } }

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 3 -Exactly -ParameterFilter { $Action -eq 'Remove' -and $PrincipalId -eq 'user-guid' }
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { $RoleDefinitionId -eq 'role-3' -and $DirectoryScopeId -eq '/administrativeUnits/au-1' -and $AssignmentType -eq 'ActivatedFromEligible' }
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            $script:CallOrder[-1] | Should -Be 'Eligible'
            $Result | Should -Contain 'Successfully removed the permanent User Administrator assignment from sseck@contoso.com'
            $Result | Should -Contain 'Successfully removed the eligible Helpdesk Administrator assignment from sseck@contoso.com'
            $Result | Should -Contain 'Successfully removed the activated Groups Administrator assignment scoped to /administrativeUnits/au-1 from sseck@contoso.com'
        }

        It 'reports a refused removal as failed and carries on with the other roles' {
            Set-UserRows -Rows @(
                (New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator')
                (New-Row -RoleId 'role-2' -RoleName 'User Administrator')
            )
            Mock -CommandName Invoke-CIPPPIMAssignmentAction -MockWith { throw [System.ArgumentException]::new('Refusing: sseck@contoso.com is the last active Global Administrator in contoso.com.') } -ParameterFilter { $RoleDefinitionId -eq $script:GlobalAdmin }

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            @($Result | Where-Object { $_ -like 'Failed to remove the permanent Global Administrator assignment from sseck@contoso.com: Refusing:*' }).Count | Should -Be 1
            $Result | Should -Contain 'Successfully removed the permanent User Administrator assignment from sseck@contoso.com'
        }
    }

    Context 'Tenant without PIM' {
        It 'deletes the unified role assignment directly' {
            Set-UserRows -Rows @(New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator' -PIMCapable $false -RoleAssignmentId 'assignment-1')

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'DELETE' -and $uri -eq 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/assignment-1'
            }
            $Result | Should -Contain 'Successfully removed the permanent Helpdesk Administrator assignment from sseck@contoso.com'
        }

        It 'falls back to the directoryRoles member reference when the row has no assignment id' {
            Set-UserRows -Rows @(New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator' -PIMCapable $false)

            $null = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq "https://graph.microsoft.com/v1.0/directoryRoles(roleTemplateId='role-1')/members/user-guid/`$ref"
            }
        }

        It 'refuses to remove the last Global Administrator' {
            Set-UserRows -Rows @(New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator' -PIMCapable $false -RoleAssignmentId 'assignment-ga')
            Set-GlobalAdminRows -Rows @(New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator' -PIMCapable $false -PrincipalId 'user-guid')

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
            @($Result | Where-Object { $_ -like 'Failed to remove the permanent Global Administrator assignment from sseck@contoso.com: *last Global Administrator*' }).Count | Should -Be 1
        }

        It 'removes Global Administrator when another administrator remains' {
            Set-UserRows -Rows @(New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator' -PIMCapable $false -RoleAssignmentId 'assignment-ga')
            Set-GlobalAdminRows -Rows @(
                (New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator' -PIMCapable $false -PrincipalId 'user-guid')
                (New-Row -RoleId $script:GlobalAdmin -RoleName 'Global Administrator' -PIMCapable $false -PrincipalId 'other-admin')
            )

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/roleAssignments/assignment-ga' }
            $Result | Should -Contain 'Successfully removed the permanent Global Administrator assignment from sseck@contoso.com'
        }

        It 'reports a Graph failure on one role and still removes the next' {
            Set-UserRows -Rows @(
                (New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator' -PIMCapable $false -RoleAssignmentId 'assignment-1')
                (New-Row -RoleId 'role-2' -RoleName 'User Administrator' -PIMCapable $false -RoleAssignmentId 'assignment-2')
            )
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Insufficient privileges to complete the operation.' } -ParameterFilter { $uri -like '*assignment-1' }

            $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

            $Result | Should -Contain 'Failed to remove the permanent Helpdesk Administrator assignment from sseck@contoso.com: Insufficient privileges to complete the operation.'
            $Result | Should -Contain 'Successfully removed the permanent User Administrator assignment from sseck@contoso.com'
        }
    }

    It 'leaves a role inherited through a role-assignable group alone' {
        Set-UserRows -Rows @(
            (New-Row -RoleId 'role-1' -RoleName 'Helpdesk Administrator' -MemberType 'Group')
            (New-Row -RoleId 'role-2' -RoleName 'User Administrator')
        )

        $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

        Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { $RoleDefinitionId -eq 'role-2' }
        @($Result | Where-Object { $_ -like 'Skipped the permanent Helpdesk Administrator assignment for sseck@contoso.com because it is inherited through a role-assignable group*' }).Count | Should -Be 1
        @($Result | Where-Object { $_ -match '^(Failed|Error)' }).Count | Should -Be 0
    }

    It 'reports a failed listing as a single failed line' {
        Mock -CommandName Get-CIPPPIMRoleAssignments -MockWith { throw 'Request failed with 403' } -ParameterFilter { $PrincipalId }

        $Result = Remove-CIPPUserRoles -Username 'sseck@contoso.com' -TenantFilter 'contoso.com' -UserID 'user-guid'

        $Result | Should -Be 'Failed to list role assignments for sseck@contoso.com: Request failed with 403'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }
}
