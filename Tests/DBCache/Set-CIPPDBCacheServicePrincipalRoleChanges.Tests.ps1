# Pester tests for Set-CIPPDBCacheServicePrincipalRoleChanges and ConvertFrom-CIPPRoleAuditEvent
# Only roles assigned to service principals are kept, with the role and who assigned it; an empty log is recorded
# as an empty set and a failed read writes nothing and rethrows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/ConvertFrom-CIPPRoleAuditEvent.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheServicePrincipalRoleChanges.ps1')

    function script:New-RoleEvent {
        param($Activity = 'Add member to role', $Actor, $TargetType = 'ServicePrincipal', [object[]]$Extra = @())
        [pscustomobject]@{
            id                  = 'evt-1'
            activityDateTime    = '2026-10-20T10:00:00Z'
            activityDisplayName = $Activity
            initiatedBy         = $Actor
            targetResources     = @(
                [pscustomobject]@{
                    id = 'sp-1'; type = $TargetType; displayName = 'Some App'
                    modifiedProperties = @(
                        [pscustomobject]@{ displayName = 'Role.DisplayName'; oldValue = $null; newValue = '"Global Administrator"' }
                        [pscustomobject]@{ displayName = 'Role.TemplateId'; oldValue = $null; newValue = '"62e90394-69f5-4237-9190-012177145e10"' }
                    )
                }
            ) + $Extra
        }
    }
}

Describe 'ConvertFrom-CIPPRoleAuditEvent' {
    It 'returns the role assigned to a service principal and the app that assigned it' {
        $Actor = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-x'; displayName = 'Other App'; servicePrincipalId = 'sp-x' } }

        $Rows = @(ConvertFrom-CIPPRoleAuditEvent -Events @(script:New-RoleEvent -Actor $Actor))

        $Rows.Count | Should -Be 1
        $Rows[0].targetId | Should -BeExactly 'sp-1'
        $Rows[0].roleId | Should -BeExactly '62e90394-69f5-4237-9190-012177145e10'
        $Rows[0].roleName | Should -BeExactly 'Global Administrator'
        $Rows[0].initiatedByType | Should -BeExactly 'Application'
        $Rows[0].initiatedByName | Should -BeExactly 'Other App'
    }

    It 'takes the role from a Role target when the event has no role properties (PIM)' {
        $User = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'admin@contoso.com' } }
        $Event = [pscustomobject]@{
            id = 'evt-2'; activityDateTime = '2026-10-20T10:00:00Z'; activityDisplayName = 'Add member to role completed (PIM activation)'; initiatedBy = $User
            targetResources = @(
                [pscustomobject]@{ id = 'role-def'; type = 'Role'; displayName = 'Exchange Administrator'; modifiedProperties = @() }
                [pscustomobject]@{ id = 'sp-2'; type = 'ServicePrincipal'; displayName = 'App'; modifiedProperties = @() }
            )
        }

        $Rows = @(ConvertFrom-CIPPRoleAuditEvent -Events @($Event))

        $Rows[0].roleId | Should -BeExactly 'role-def'
        $Rows[0].roleName | Should -BeExactly 'Exchange Administrator'
        $Rows[0].initiatedByType | Should -BeExactly 'User'
        $Rows[0].initiatedByName | Should -BeExactly 'admin@contoso.com'
    }

    It 'ignores users, eligible assignments and removals' {
        $Events = @(
            script:New-RoleEvent -TargetType 'User'
            script:New-RoleEvent -Activity 'Add eligible member to role in PIM completed (permanent)'
            script:New-RoleEvent -Activity 'Remove member from role'
        )

        @(ConvertFrom-CIPPRoleAuditEvent -Events $Events).Count | Should -Be 0
    }

    It 'returns the group a service principal was added to' {
        $Event = [pscustomobject]@{
            id = 'evt-3'; activityDateTime = '2026-10-20T10:00:00Z'; activityDisplayName = 'Add member to group'
            initiatedBy = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-x'; displayName = 'Other App'; servicePrincipalId = 'sp-x' } }
            targetResources = @(
                [pscustomobject]@{
                    id = 'sp-3'; type = 'ServicePrincipal'; displayName = 'App'
                    modifiedProperties = @(
                        [pscustomobject]@{ displayName = 'Group.ObjectID'; oldValue = $null; newValue = '"grp-1"' }
                        [pscustomobject]@{ displayName = 'Group.DisplayName'; oldValue = $null; newValue = '"Tier 0 Apps"' }
                    )
                }
            )
        }

        $Rows = @(ConvertFrom-CIPPRoleAuditEvent -Events @($Event))

        $Rows.Count | Should -Be 1
        $Rows[0].targetId | Should -BeExactly 'sp-3'
        $Rows[0].groupId | Should -BeExactly 'grp-1'
        $Rows[0].groupName | Should -BeExactly 'Tier 0 Apps'
        $Rows[0].roleId | Should -BeNullOrEmpty
        $Rows[0].initiatedByType | Should -BeExactly 'Application'
    }
}

Describe 'Set-CIPPDBCacheServicePrincipalRoleChanges' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'reads 30 days of RoleManagement events app-only and caches them' {
        Mock New-GraphGetRequest { if ($uri -like "*category eq 'RoleManagement'*") { script:New-RoleEvent } }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*directoryAudits?`$filter=category eq 'RoleManagement' and activityDateTime ge *" -and $AsApp -and $Stream }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'ServicePrincipalRoleChanges' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
    }

    It 'reads group membership events only for role-assignable groups' {
        Mock New-GraphGetRequest {
            if ($uri -like '*/groups?*') { [pscustomobject]@{ id = 'grp-a' }; [pscustomobject]@{ id = 'grp-b' } }
        }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/groups?$filter=isAssignableToRole eq true*' }
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*category eq 'GroupManagement' and activityDisplayName eq 'Add member to group' and activityDateTime ge * and targetResources/any(t:t/id eq 'grp-a' or t/id eq 'grp-b')&*" -and $AsApp -and $Stream }
        Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like "*category eq 'GroupManagement'*" -and $uri -notlike '*targetResources/any*' }
    }

    It 'reads the groups 20 at a time, each group exactly once' {
        Mock New-GraphGetRequest {
            if ($uri -like '*/groups?*') { 1..45 | ForEach-Object { [pscustomobject]@{ id = "grp-$_" } } }
        }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 3 -Exactly -ParameterFilter { $uri -like "*category eq 'GroupManagement'*" }
        foreach ($Size in 20, 20, 5) {
            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like "*category eq 'GroupManagement'*" -and ([regex]::Matches($uri, "t/id eq 'grp-\d+'")).Count -eq $Size }
        }
        foreach ($n in 1, 20, 21, 40, 41, 45) {
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*t/id eq 'grp-$n'[) ]*" }
        }
    }

    It 'skips the group membership read when the tenant has no role-assignable group' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like "*category eq 'GroupManagement'*" }
    }

    It 'keeps only events with a service principal target' {
        $GroupEvent = {
            param($MemberType)
            [pscustomobject]@{
                id = "evt-$MemberType"; activityDateTime = '2026-10-20T10:00:00Z'; activityDisplayName = 'Add member to group'
                initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'admin@contoso.com' } }
                targetResources = @(
                    [pscustomobject]@{ id = "$MemberType-1"; type = $MemberType; modifiedProperties = @([pscustomobject]@{ displayName = 'Group.ObjectID'; newValue = '"grp-a"' }) }
                    [pscustomobject]@{ id = 'grp-a'; type = 'Group'; modifiedProperties = @() }
                )
            }
        }
        Mock New-GraphGetRequest {
            if ($uri -like '*/groups?*') { [pscustomobject]@{ id = 'grp-a' } }
            elseif ($uri -like "*category eq 'GroupManagement'*") { & $GroupEvent 'User'; & $GroupEvent 'ServicePrincipal'; & $GroupEvent 'User' }
        }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { @($Data).Count -eq 1 -and $Data[0].targetId -eq 'ServicePrincipal-1' -and $Data[0].groupId -eq 'grp-a' }
    }

    It 'writes nothing and rethrows when a group membership read fails' {
        Mock New-GraphGetRequest {
            if ($uri -like '*/groups?*') { [pscustomobject]@{ id = 'grp-a' } }
            elseif ($uri -like "*category eq 'GroupManagement'*") { throw 'Too many requests' }
        }

        { Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Too many requests*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }

    It 'records an empty set when no role was assigned to an app' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when the audit log cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheServicePrincipalRoleChanges -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}
