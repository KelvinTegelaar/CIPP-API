# Pester tests for Invoke-ExecEnterpriseAppExchangeRbac, Invoke-ListEnterpriseAppExchangeRbac and
# Invoke-ListExoAppMailboxAccess. Exchange is mocked per cmdlet; every write is recorded in order so tests can
# check what was sent and when.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function Set-CIPPDBCacheExoAppRoleAssignments { param($TenantFilter) }
    function Set-CIPPDBCacheExoApplicationAccessPolicies { param($TenantFilter) }
    function Get-CIPPRiskyPermissionCatalog {
        $ExchangeRole = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ExchangeRole['Application Mail.Read'] = [pscustomobject]@{ name = 'Application Mail.Read'; impact = 'Critical'; suspicion = 'Low' }
        [pscustomobject]@{ ExchangeRole = $ExchangeRole }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPExoAppRoleAssignment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPExoApplicationAccessPolicy.ps1')
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval'
    foreach ($Name in 'Invoke-ExecEnterpriseAppExchangeRbac.ps1', 'Invoke-ListEnterpriseAppExchangeRbac.ps1', 'Invoke-ListExoAppMailboxAccess.ps1') {
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $Folder $Name) -Raw)))
    }

    $script:Sp = '11111111-1111-1111-1111-111111111111'
    $script:OtherSp = '22222222-2222-2222-2222-222222222222'
    $script:AdminUnit = '33333333-3333-3333-3333-333333333333'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = $script:Sp }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecEnterpriseAppExchangeRbac' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]$Merged
        }
    }
    # Pester does not take a BeforeEach at the file root: each Describe calls this from its own.
    function script:Initialize-ExoMocks {
        [System.Environment]::SetEnvironmentVariable('ApplicationID', 'cipp-sam-app')
        $script:AppId = 'app-1'
        $script:Registered = $true
        $script:ExoAssignments = @()
        $script:Policies = @()
        $script:Writes = [System.Collections.Generic.List[object]]::new()

        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Sp; appId = $script:AppId; displayName = 'Contoso App' } }
        Mock Set-CIPPDBCacheExoAppRoleAssignments { }
        Mock Set-CIPPDBCacheExoApplicationAccessPolicies { }
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ServicePrincipal' {
                    [pscustomobject]@{ Identity = 'exo-other'; ObjectId = $script:OtherSp; AppId = 'app-2'; DisplayName = 'Other App' }
                    if ($script:Registered) { [pscustomobject]@{ Identity = 'exo-1'; ObjectId = $script:Sp; AppId = $script:AppId; DisplayName = 'Contoso App' } }
                }
                'Get-ManagementRoleAssignment' { $script:ExoAssignments }
                'Get-ManagementRole' {
                    [pscustomobject]@{ Name = 'Application Mail.Read'; Description = 'Read mail' }
                    [pscustomobject]@{ Name = 'Application Calendars.Read'; Description = 'Read calendars' }
                    [pscustomobject]@{ Name = 'Mail Recipients'; Description = 'Admin role' }
                }
                'Get-ManagementScope' {
                    [pscustomobject]@{ Name = 'Sales'; RecipientFilter = "Department -eq 'Sales'"; Exclusive = $false }
                    [pscustomobject]@{ Name = 'VIP'; RecipientFilter = "CustomAttribute1 -eq 'VIP'"; Exclusive = $true }
                }
                'Get-ApplicationAccessPolicy' { $script:Policies }
                default { $script:Writes.Add([pscustomobject]@{ Cmdlet = $cmdlet; Params = $cmdParams }) }
            }
        }
    }
    function Get-Writes { param($Cmdlet) @($script:Writes | Where-Object { -not $Cmdlet -or $_.Cmdlet -eq $Cmdlet }) }
}

AfterAll {
    [System.Environment]::SetEnvironmentVariable('ApplicationID', $null)
}

Describe 'Invoke-ExecEnterpriseAppExchangeRbac' {
    BeforeEach { Initialize-ExoMocks }

    Context 'input validation' {
        It 'rejects an unknown action' {
            (Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'Nuke' })).StatusCode | Should -Be 400
        }
        It 'rejects an administrative unit scope without a valid unit' {
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Application Mail.Read'); ScopeType = 'AdministrativeUnit'; AdministrativeUnit = 'x' })
            $Response.StatusCode | Should -Be 400
            Get-Writes | Should -BeNullOrEmpty
        }
        It 'refuses to change the CIPP-SAM application itself' {
            $script:AppId = 'cipp-sam-app'
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Application Mail.Read'); ScopeType = 'Organization' })
            $Response.Body.Results[0].state | Should -Be 'error'
            Get-Writes | Should -BeNullOrEmpty
        }
    }

    Context 'AddRoles' {
        It 'registers an unregistered app in Exchange, then assigns the role organisation-wide' {
            $script:Registered = $false
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @(@{ label = 'Application Mail.Read'; value = 'Application Mail.Read' }); ScopeType = @{ value = 'Organization' } })

            $Response.StatusCode | Should -Be 200
            (Get-Writes).Cmdlet | Should -Be @('New-ServicePrincipal', 'New-ManagementRoleAssignment')
            (Get-Writes 'New-ServicePrincipal')[0].Params.ObjectId | Should -Be $script:Sp
            $Assign = (Get-Writes 'New-ManagementRoleAssignment')[0].Params
            $Assign.App | Should -Be $script:Sp
            $Assign.Role | Should -Be 'Application Mail.Read'
            $Assign.ContainsKey('CustomResourceScope') | Should -BeFalse
            $Assign.ContainsKey('RecipientAdministrativeUnitScope') | Should -BeFalse
        }

        It 'scopes the role to a management scope or administrative unit, and skips one already held with that scope' {
            $script:ExoAssignments = @([pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-1'; Enabled = $true; CustomResourceScope = 'Sales' })

            $null = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Application Mail.Read', 'Application Calendars.Read'); ScopeType = 'ManagementScope'; ManagementScope = @{ value = 'Sales' } })
            $null = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Application Mail.Read'); ScopeType = 'AdministrativeUnit'; AdministrativeUnit = @{ label = 'Finance'; value = $script:AdminUnit } })

            $Assigns = Get-Writes 'New-ManagementRoleAssignment'
            $Assigns.Count | Should -Be 2
            $Assigns[0].Params.Role | Should -Be 'Application Calendars.Read'
            $Assigns[0].Params.CustomResourceScope | Should -Be 'Sales'
            $Assigns[1].Params.RecipientAdministrativeUnitScope | Should -Be $script:AdminUnit
            Get-Writes 'New-ServicePrincipal' | Should -BeNullOrEmpty
        }

        It 'refuses a role that is not an Application role' {
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Mail Recipients'); ScopeType = 'Organization' })

            $Response.Body.Results[0].resultText | Should -BeLike '*Unknown Application role(s): Mail Recipients*'
            Get-Writes | Should -BeNullOrEmpty
        }
    }

    Context 'ChangeScope and RemoveRoles' {
        BeforeEach {
            $script:ExoAssignments = @(
                [pscustomobject]@{ Guid = 'ra-own'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-1'; Enabled = $true }
                [pscustomobject]@{ Guid = 'ra-other'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-other'; Enabled = $true }
            )
        }

        It 'assigns the role with the new scope before removing the old assignment' {
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'ChangeScope'; AssignmentIds = @('ra-own'); ScopeType = 'ManagementScope'; ManagementScope = 'Sales' })

            $Response.StatusCode | Should -Be 200
            (Get-Writes).Cmdlet | Should -Be @('New-ManagementRoleAssignment', 'Remove-ManagementRoleAssignment')
            (Get-Writes 'New-ManagementRoleAssignment')[0].Params.CustomResourceScope | Should -Be 'Sales'
            (Get-Writes 'Remove-ManagementRoleAssignment')[0].Params.Identity | Should -Be 'ra-own'
        }

        It 'removes only assignments that belong to the app' {
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'RemoveRoles'; AssignmentIds = @('ra-own', 'ra-other') })

            @(Get-Writes 'Remove-ManagementRoleAssignment').Params.Identity | Should -Be @('ra-own')
            $Response.Body.Results.state | Should -Be @('success', 'error')
            $Response.Body.Results[1].resultText | Should -BeLike '*ra-other does not belong to Contoso App*'
        }
    }

    Context 'RemovePolicies and NewScope' {
        It 'removes the app''s own policy and refuses one that applies to every app' {
            $script:Policies = @(
                [pscustomobject]@{ Identity = 'contoso\pol-own'; AppId = 'app-1'; AccessRight = 'RestrictAccess'; ScopeName = 'Sales' }
                [pscustomobject]@{ Identity = 'contoso\pol-all'; AppId = '*'; AccessRight = 'DenyAccess'; ScopeName = 'Board' }
            )

            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'RemovePolicies'; PolicyIds = @('contoso\pol-own', 'contoso\pol-all') })

            @(Get-Writes 'Remove-ApplicationAccessPolicy').Params.Identity | Should -Be @('contoso\pol-own')
            $Response.Body.Results[1].resultText | Should -BeLike '*applies to every app*'
        }

        It 'creates a management scope from a name and recipient filter' {
            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'NewScope'; ScopeName = 'Finance'; RecipientFilter = "Department -eq 'Finance'" })

            $Response.StatusCode | Should -Be 200
            $Params = (Get-Writes 'New-ManagementScope')[0].Params
            $Params.Name | Should -Be 'Finance'
            $Params.RecipientRestrictionFilter | Should -Be "Department -eq 'Finance'"
        }
    }

    Context 'cache refresh for the permission exposure report' {
        It 'refreshes the role assignment cache after a role change, and keeps the result when the refresh fails' {
            Mock Set-CIPPDBCacheExoAppRoleAssignments { throw 'cache down' }

            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'AddRoles'; Roles = @('Application Mail.Read'); ScopeType = 'Organization' })

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results[0].state | Should -Be 'success'
            Should -Invoke Set-CIPPDBCacheExoAppRoleAssignments -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' }
            Should -Invoke Set-CIPPDBCacheExoApplicationAccessPolicies -Times 0 -Exactly
        }

        It 'refreshes the policy cache after a policy removal, and nothing when every change failed or was a scope change' {
            $script:Policies = @([pscustomobject]@{ Identity = 'contoso\pol-own'; AppId = 'app-1'; AccessRight = 'RestrictAccess'; ScopeName = 'Sales' })

            $null = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'RemovePolicies'; PolicyIds = @('contoso\pol-own') })
            $null = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'RemovePolicies'; PolicyIds = @('contoso\missing') })
            $null = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'NewScope'; ScopeName = 'Finance'; RecipientFilter = "Department -eq 'Finance'" })

            Should -Invoke Set-CIPPDBCacheExoApplicationAccessPolicies -Times 1 -Exactly
            Should -Invoke Set-CIPPDBCacheExoAppRoleAssignments -Times 0 -Exactly
        }
    }

    Context 'tenant-level actions, without an app' {
        It 'requires an app for role actions' {
            (Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ ServicePrincipalId = ''; Action = 'RemoveRoles'; AssignmentIds = @('ra-1') })).StatusCode | Should -Be 400
        }

        It 'removes any policy, also one for every app, but refuses from one app a policy that names others too' {
            $script:Policies = @(
                [pscustomobject]@{ Identity = 'contoso\pol-all'; AppId = '*'; AccessRight = 'DenyAccess'; ScopeName = 'Board' }
                [pscustomobject]@{ Identity = 'contoso\pol-shared'; AppId = @('app-1', 'app-2'); AccessRight = 'RestrictAccess'; ScopeName = 'Sales' }
            )

            $FromApp = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ Action = 'RemovePolicies'; PolicyIds = @('contoso\pol-shared') })
            $FromTenant = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ ServicePrincipalId = ''; Action = 'RemovePolicies'; PolicyIds = @('contoso\pol-all', 'contoso\pol-shared') })

            $FromApp.Body.Results[0].resultText | Should -BeLike '*also applies to other apps*'
            $FromTenant.StatusCode | Should -Be 200
            @(Get-Writes 'Remove-ApplicationAccessPolicy').Params.Identity | Should -Be @('contoso\pol-all', 'contoso\pol-shared')
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        }

        It 'removes an unused management scope and keeps one any role assignment uses' {
            $script:ExoAssignments = @([pscustomobject]@{ Guid = 'ra-admin'; Role = 'Mail Recipients'; RoleAssignee = 'Helpdesk'; CustomRecipientWriteScope = 'Sales' })

            $Response = Invoke-ExecEnterpriseAppExchangeRbac -Request (New-Request @{ ServicePrincipalId = ''; Action = 'RemoveScope'; ScopeNames = @('Sales', 'Unused') })

            @(Get-Writes 'Remove-ManagementScope').Params.Identity | Should -Be @('Unused')
            $Response.Body.Results[0].resultText | Should -BeLike '*Sales is used by 1 role assignment(s)*'
        }
    }
}

Describe 'Invoke-ListEnterpriseAppExchangeRbac' {
    BeforeEach { Initialize-ExoMocks }

    It 'returns the app''s registration, own assignments, applying policies, Application roles and scopes' {
        $script:ExoAssignments = @(
            [pscustomobject]@{ Guid = 'ra-own'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-1'; Enabled = $true; CustomResourceScope = 'Sales' }
            [pscustomobject]@{ Guid = 'ra-other'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-other'; Enabled = $true }
        )
        $script:Policies = @(
            [pscustomobject]@{ Identity = 'contoso\pol-own'; AppId = 'app-1'; AccessRight = 'RestrictAccess'; ScopeName = 'Sales' }
            [pscustomobject]@{ Identity = 'contoso\pol-all'; AppId = '*'; AccessRight = 'DenyAccess'; ScopeName = 'Board' }
            [pscustomobject]@{ Identity = 'contoso\pol-x'; AppId = 'app-2'; AccessRight = 'RestrictAccess'; ScopeName = 'X' }
        )
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListEnterpriseAppExchangeRbac' }; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = $script:Sp }; Body = $null }

        $Response = Invoke-ListEnterpriseAppExchangeRbac -Request $Request
        $Result = $Response.Body.Results

        $Response.StatusCode | Should -Be 200
        $Result.registered | Should -BeTrue
        @($Result.assignments).id | Should -Be @('ra-own')
        @($Result.assignments)[0].customResourceScopeFilter | Should -Be "Department -eq 'Sales'"
        @($Result.accessPolicies).policyIdentity | Should -Be @('contoso\pol-own', 'contoso\pol-all')
        @($Result.accessPolicies).appliesToEveryApp | Should -Be @($false, $true)
        @($Result.availableRoles).name | Should -Be @('Application Calendars.Read', 'Application Mail.Read')
        @($Result.managementScopes | Where-Object exclusive).name | Should -Be @('VIP')
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-ServicePrincipal' }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-ManagementScope' }
    }

    It 'rejects a non-GUID ServicePrincipalId' {
        $Request = [pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = 'x' }; Body = $null }
        (Invoke-ListEnterpriseAppExchangeRbac -Request $Request).StatusCode | Should -Be 400
    }
}

Describe 'Invoke-ListExoAppMailboxAccess' {
    BeforeEach { Initialize-ExoMocks }

    BeforeAll {
        function Get-List {
            param($Type, $Tenant = 'contoso.onmicrosoft.com')
            Invoke-ListExoAppMailboxAccess -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = $Tenant; Type = $Type }; Body = $null })
        }
    }

    It 'refuses all tenants and an unknown type' {
        (Get-List -Type 'Roles' -Tenant 'AllTenants').StatusCode | Should -Be 400
        (Get-List -Type 'Everything').StatusCode | Should -Be 400
    }

    It 'lists every app''s role assignments with the app name, scope and catalog impact' {
        $script:ExoAssignments = @(
            [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-1'; Enabled = $true; CustomResourceScope = 'Sales' }
            [pscustomobject]@{ Guid = 'ra-2'; Role = 'Application Calendars.Read'; RoleAssignee = 'exo-other'; Enabled = $true }
            [pscustomobject]@{ Guid = 'ra-3'; Role = 'Mail Recipients'; RoleAssignee = 'Helpdesk'; Enabled = $true }
        )

        $Rows = @((Get-List -Type 'Roles').Body.Results)

        $Rows.id | Should -Be @('ra-1', 'ra-2')
        $Rows[0].appDisplayName | Should -Be 'Contoso App'
        $Rows[0].scope | Should -Be 'Management scope'
        $Rows[0].scopeName | Should -Be 'Sales'
        $Rows[0].impact | Should -Be 'Critical'
        $Rows[1].scope | Should -Be 'Organization'
        $Rows[1].impact | Should -BeNullOrEmpty
    }

    It 'lists each policy once with the apps it names' {
        $script:Policies = @(
            [pscustomobject]@{ Identity = 'contoso\pol-1'; AppId = @('app-1', 'app-gone'); AccessRight = 'RestrictAccess'; ScopeName = 'Sales'; IsValid = $true }
            [pscustomobject]@{ Identity = 'contoso\pol-2'; AppId = '*'; AccessRight = 'DenyAccess'; ScopeName = 'Board'; IsValid = $true }
        )

        $Rows = @((Get-List -Type 'Policies').Body.Results)

        $Rows.policyIdentity | Should -Be @('contoso\pol-1', 'contoso\pol-2')
        $Rows[0].appNames | Should -Be 'Contoso App, app-gone (not in this tenant)'
        $Rows[0].servicePrincipalId | Should -Be $script:Sp
        $Rows[1].appNames | Should -Be 'Every app'
        $Rows[1].appliesToEveryApp | Should -BeTrue
        $Rows[1].servicePrincipalId | Should -BeNullOrEmpty
    }

    It 'counts the app and other role assignments using each scope' {
        $script:ExoAssignments = @(
            [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'exo-1'; CustomResourceScope = 'Sales' }
            [pscustomobject]@{ Guid = 'ra-2'; Role = 'Mail Recipients'; RoleAssignee = 'Helpdesk'; CustomRecipientWriteScope = 'Sales' }
        )

        $Rows = @((Get-List -Type 'Scopes').Body.Results)

        $Rows.name | Should -Be @('Sales', 'VIP')
        $Rows[0].appAssignmentCount | Should -Be 1
        $Rows[0].otherAssignmentCount | Should -Be 1
        $Rows[1].appAssignmentCount | Should -Be 0
        $Rows[1].exclusive | Should -BeTrue
    }

    It 'lists only Application roles as assignable, with their impact' {
        $Rows = @((Get-List -Type 'AvailableRoles').Body.Results)

        $Rows.name | Should -Be @('Application Calendars.Read', 'Application Mail.Read')
        $Rows[1].impact | Should -Be 'Critical'
    }
}
