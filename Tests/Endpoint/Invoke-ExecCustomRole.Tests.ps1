# Pester tests for Invoke-ExecCustomRole
#
# Focused on the cache fanout: changing which Entra group maps to a role must clear the
# cached per-user role resolutions (cacheAccessUserRoles) and refresh the allowedUsers
# projection, not just bump the access-scope version. Permission-only edits must NOT pay
# for a full user re-sync.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecCustomRole.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecCustomRole.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # The endpoint reads Config\cipp-roles.json relative to CIPPRootPath.
    $script:OriginalCippRootPath = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Clear-CippAccessScopeCache { }
    function Clear-CippAccessUserCache { }
    function Start-UserSyncTimer { }
    function ConvertTo-CippPermissionRules { param($Permissions) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $AsApp) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    function New-RoleRequest {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCustomRole' }
            Query   = [pscustomobject]@{ }
            Headers = @{ }
            Body    = [pscustomobject]$Body
        }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalCippRootPath
}

Describe 'Invoke-ExecCustomRole group mapping fanout' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Clear-CippAccessScopeCache -MockWith { }
        Mock -CommandName Clear-CippAccessUserCache -MockWith { }
        Mock -CommandName Start-UserSyncTimer -MockWith { }
    }

    It 'clears the user role cache when a group is first mapped to a role' {
        $Request = New-RoleRequest @{
            Action     = 'AddUpdate'
            RoleName   = 'admin'
            EntraGroup = [pscustomobject]@{ label = 'CIPP Admins'; value = 'guid-1' }
        }

        $Response = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 1 -Exactly
        Should -Invoke Clear-CippAccessScopeCache -Times 1 -Exactly
    }

    It 'clears the user role cache when the mapped group changes' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'admin'; GroupId = 'guid-old'; GroupName = 'Old Group' }
        } -ParameterFilter { $TableName -eq 'AccessRoleGroups' }

        $Request = New-RoleRequest @{
            Action     = 'AddUpdate'
            RoleName   = 'admin'
            EntraGroup = [pscustomobject]@{ label = 'CIPP Admins'; value = 'guid-1' }
        }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 1 -Exactly
    }

    It 'does not re-sync when the mapping is saved unchanged' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'admin'; GroupId = 'guid-1'; GroupName = 'CIPP Admins' }
        } -ParameterFilter { $TableName -eq 'AccessRoleGroups' }

        $Request = New-RoleRequest @{
            Action     = 'AddUpdate'
            RoleName   = 'admin'
            EntraGroup = [pscustomobject]@{ label = 'CIPP Admins'; value = 'guid-1' }
        }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Clear-CippAccessUserCache -Times 0 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 0 -Exactly
        # The scope-rule stamp still bumps on every role save.
        Should -Invoke Clear-CippAccessScopeCache -Times 1 -Exactly
    }

    It 'clears the user role cache when a mapping is removed on save' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'admin'; GroupId = 'guid-1'; GroupName = 'CIPP Admins' }
        } -ParameterFilter { $TableName -eq 'AccessRoleGroups' }

        $Request = New-RoleRequest @{
            Action   = 'AddUpdate'
            RoleName = 'admin'
        }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AccessRoleGroups' }
        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 1 -Exactly
    }

    It 'clears the user role cache when deleting a role that had a mapping' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AccessRoleGroups'; RowKey = 'testrole'; GroupId = 'guid-1'; GroupName = 'CIPP Admins' }
        } -ParameterFilter { $TableName -eq 'AccessRoleGroups' }

        $Request = New-RoleRequest @{
            Action   = 'Delete'
            RoleName = 'testrole'
        }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 1 -Exactly
    }

    It 'does not touch the user role cache when deleting a role with no mapping' {
        $Request = New-RoleRequest @{
            Action   = 'Delete'
            RoleName = 'testrole'
        }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Clear-CippAccessUserCache -Times 0 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 0 -Exactly
        Should -Invoke Clear-CippAccessScopeCache -Times 1 -Exactly
    }
}

Describe 'Invoke-ExecCustomRole app role tenants' {
    BeforeAll {
        $script:TenantA = '11111111-1111-1111-1111-111111111111'
        $script:TenantB = '22222222-2222-2222-2222-222222222222'
    }

    BeforeEach {
        $script:OriginalClientId = [Environment]::GetEnvironmentVariable('WEBSITE_AUTH_CLIENT_ID')
        [Environment]::SetEnvironmentVariable('WEBSITE_AUTH_CLIENT_ID', 'sso-app-id')
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Clear-CippAccessScopeCache -MockWith { }
        Mock -CommandName Clear-CippAccessUserCache -MockWith { }
        Mock -CommandName Start-UserSyncTimer -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'app-object-id'; appRoles = @([pscustomobject]@{ value = 'readonly' }) }
        }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('WEBSITE_AUTH_CLIENT_ID', $script:OriginalClientId)
    }

    It 'grants the role to each valid tenant and adds the app role to the SSO app' {
        $Request = New-RoleRequest @{
            Action         = 'AddUpdate'
            RoleName       = 'Editor'
            AppRoleTenants = @([pscustomobject]@{ label = $TenantA.ToUpper(); value = $TenantA.ToUpper() }, 'not-a-tenant')
        }

        $Response = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'allowedAppRoles' -and $Entity.PartitionKey -eq $TenantA -and $Entity.RowKey -ceq 'editor'
        }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Roles = ($body | ConvertFrom-Json).appRoles
            $type -eq 'PATCH' -and $uri -like '*/applications/app-object-id' -and
            ($Roles.value -join ',') -eq 'readonly,editor'
        }
        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
        $Response.Body.Results | Should -Contain "Ignored app role tenant 'not-a-tenant': not a tenant ID"
    }

    It 'leaves the SSO app alone when the app role already exists' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'app-object-id'; appRoles = @([pscustomobject]@{ value = 'editor' }) }
        }
        $Request = New-RoleRequest @{ Action = 'AddUpdate'; RoleName = 'editor'; AppRoleTenants = @($TenantA) }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'revokes tenants that were removed and keeps the rest' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = $TenantA; RowKey = 'editor' }
            [pscustomobject]@{ PartitionKey = $TenantB; RowKey = 'editor' }
        } -ParameterFilter { $TableName -eq 'allowedAppRoles' }
        $Request = New-RoleRequest @{ Action = 'AddUpdate'; RoleName = 'editor'; AppRoleTenants = @($TenantA) }

        $null = Invoke-ExecCustomRole -Request $Request -TriggerMetadata $null

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PartitionKey -eq $TenantB }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'allowedAppRoles' }
        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
    }

    It 'does not touch app roles or the user cache when none are configured' {
        $null = Invoke-ExecCustomRole -Request (New-RoleRequest @{ Action = 'AddUpdate'; RoleName = 'editor' }) -TriggerMetadata $null

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Clear-CippAccessUserCache -Times 0 -Exactly
    }

    It 'lists built-in roles with their app role tenants even when there are no custom roles' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = $TenantA; RowKey = 'editor' }
        } -ParameterFilter { $TableName -eq 'allowedAppRoles' }

        $Response = Invoke-ExecCustomRole -Request (New-RoleRequest @{ }) -TriggerMetadata $null

        $Editor = @($Response.Body).Where({ $_.RowKey -eq 'editor' })
        $Editor.Count | Should -Be 1
        $Editor[0].AppRoleTenants | Should -Be @($TenantA)
    }

    It 'removes the role from every tenant when the role is deleted' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = $TenantA; RowKey = 'testrole' }
        } -ParameterFilter { $TableName -eq 'allowedAppRoles' }

        $null = Invoke-ExecCustomRole -Request (New-RoleRequest @{ Action = 'Delete'; RoleName = 'testrole' }) -TriggerMetadata $null

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PartitionKey -eq $TenantA }
        Should -Invoke Clear-CippAccessUserCache -Times 1 -Exactly
    }
}

Describe 'Clear-CippAccessUserCache' {
    BeforeAll {
        $HelperPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Clear-CippAccessUserCache.ps1' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $HelperPath) { throw 'Could not locate Clear-CippAccessUserCache.ps1 under Modules/' }
        . $HelperPath
    }

    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = 'cacheAccessUserRoles' } }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
    }

    It 'removes every cached AccessUser row' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ PartitionKey = 'AccessUser'; RowKey = 'a@contoso.com' }
                [pscustomobject]@{ PartitionKey = 'AccessUser'; RowKey = 'b@contoso.com' }
            )
        }

        Clear-CippAccessUserCache

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 2 -Exactly
    }

    It 'does nothing when the cache is empty' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }

        Clear-CippAccessUserCache

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'logs instead of throwing when storage is unavailable' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { throw 'storage offline' }

        { Clear-CippAccessUserCache } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -Exactly
    }
}
