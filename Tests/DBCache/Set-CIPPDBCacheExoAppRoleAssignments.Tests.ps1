# Pester tests for Set-CIPPDBCacheExoAppRoleAssignments and Get-CIPPExoAppRoleAssignment
# Only 'Application *' role assignments are kept, matched to the app's Entra ids; Exchange is not asked for
# assignments when no service principal is registered there; an empty read is recorded as an empty set and a
# failed read writes nothing and rethrows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPExoAppRoleAssignment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheExoAppRoleAssignments.ps1')

    $script:ExoSp = [pscustomobject]@{ Identity = 'a1b2'; Name = 'a1b2'; AppId = 'app-1'; ObjectId = 'sp-1'; DisplayName = 'Mail Sync' }
}

Describe 'Get-CIPPExoAppRoleAssignment' {
    It 'keeps only application roles, matched to the app''s Entra ids, with the filter of a management scope' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ServicePrincipal' { $script:ExoSp }
                'Get-ManagementRoleAssignment' {
                    [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssigneeName = 'Mail Sync'; Enabled = $true; CustomResourceScope = 'Sales'; WhenCreatedUTC = '2026-10-01T00:00:00Z' }
                    [pscustomobject]@{ Guid = 'ra-2'; Role = 'Application Calendars.Read'; RoleAssignee = 'a1b2'; Enabled = $true; RecipientAdministrativeUnitScope = 'au-1' }
                    [pscustomobject]@{ Guid = 'ra-3'; Role = 'Mail Recipients'; RoleAssignee = 'Organization Management'; Enabled = $true }
                }
                'Get-ManagementScope' { [pscustomobject]@{ Name = 'Sales'; RecipientFilter = "Department -eq 'Sales'" } }
            }
        }

        $Rows = @(Get-CIPPExoAppRoleAssignment -TenantFilter 'contoso.onmicrosoft.com')

        $Rows.Count | Should -Be 2
        $Rows.role | Should -Be @('Application Mail.Read', 'Application Calendars.Read')
        $Rows.servicePrincipalId | Should -Be @('sp-1', 'sp-1')
        $Rows[0].appId | Should -BeExactly 'app-1'
        $Rows[0].customResourceScopeFilter | Should -BeExactly "Department -eq 'Sales'"
        $Rows[1].recipientAdministrativeUnitScope | Should -BeExactly 'au-1'
    }

    It 'does not read assignments when no service principal is registered in Exchange' {
        Mock New-ExoRequest { }

        @(Get-CIPPExoAppRoleAssignment -TenantFilter 'contoso.onmicrosoft.com').Count | Should -Be 0
        Should -Invoke New-ExoRequest -Times 1 -Exactly
        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Get-ManagementRoleAssignment' }
    }

    It 'leaves out a scope filter it cannot read' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ServicePrincipal' { $script:ExoSp }
                'Get-ManagementRoleAssignment' { [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'a1b2'; Enabled = $true; CustomResourceScope = 'Sales' } }
                'Get-ManagementScope' { throw 'Access denied' }
            }
        }

        $Rows = @(Get-CIPPExoAppRoleAssignment -TenantFilter 'contoso.onmicrosoft.com')

        $Rows[0].customResourceScope | Should -BeExactly 'Sales'
        $Rows[0].customResourceScopeFilter | Should -BeNullOrEmpty
    }

    It 'does not ask for management scopes when no role uses one' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ServicePrincipal' { $script:ExoSp }
                'Get-ManagementRoleAssignment' { [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'a1b2'; Enabled = $true } }
            }
        }
        $null = Get-CIPPExoAppRoleAssignment -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Get-ManagementScope' }
    }
}

Describe 'Set-CIPPDBCacheExoAppRoleAssignments' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'caches the application role assignments' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ServicePrincipal' { $script:ExoSp }
                'Get-ManagementRoleAssignment' { [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'a1b2'; Enabled = $true } }
            }
        }

        Set-CIPPDBCacheExoAppRoleAssignments -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'ExoAppRoleAssignments' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
    }

    It 'records an empty set when no app holds an application role' {
        Mock New-ExoRequest { }

        Set-CIPPDBCacheExoAppRoleAssignments -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when Exchange cannot be read' {
        Mock New-ExoRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheExoAppRoleAssignments -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}
