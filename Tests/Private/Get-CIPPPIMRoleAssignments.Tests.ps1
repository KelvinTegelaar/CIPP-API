# Pester tests for Get-CIPPPIMRoleAssignments.
#
# A partner's GDAP group holds a directory role in the customer tenant but lives in the partner
# tenant, so it never resolves there. Those rows used to come back as PrincipalType 'Unknown' with
# no name. They must be labelled as foreign with the owning tenant, while a principal that
# is simply gone (same tenant, unresolvable) stays Unknown.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPPIMRoleAssignments.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CIPPPIMRoleAssignments.ps1 under Modules/' }

    function Get-CIPPPrivilegedRoleTemplateIds { param([switch]$WithNames) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $AsApp, $NoAuthCheck) }
    function New-GraphBulkRequest { param($tenantid, $NoAuthCheck, $asapp, $Requests, $Version) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPPartnerTenantList { }

    . (Join-Path (Split-Path -Parent $FunctionPath) 'Get-CIPPForeignPrincipalInfo.ps1')
    . $FunctionPath
    # The foreign-principal check treats $env:TenantID as one of our partners, so pin it.
    $script:OriginalTenantID = $env:TenantID
    $env:TenantID = 'cipp-partner'
}

AfterAll {
    $env:TenantID = $script:OriginalTenantID
}

Describe 'Get-CIPPPIMRoleAssignments foreign principals' {
    BeforeEach {
        Mock Get-CIPPPrivilegedRoleTemplateIds { @() }
        # No PIM licence: the unified roleAssignments list is the source.
        Mock Test-CIPPStandardLicense { $false }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'home-tenant' } }
        Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*roleDefinitions*' }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'a1'; principalId = 'user-1'; principalOrganizationId = 'home-tenant'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
                [pscustomobject]@{ id = 'a2'; principalId = 'gdap-group'; principalOrganizationId = 'partner-tenant'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
                [pscustomobject]@{ id = 'a3'; principalId = 'deleted-user'; principalOrganizationId = 'home-tenant'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
            )
        } -ParameterFilter { $uri -like '*roleAssignments*' }
        # getByIds only knows the principal that lives in this tenant.
        Mock Get-CIPPPartnerTenantList { @() }
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'user-1'; '@odata.type' = '#microsoft.graph.user'; displayName = 'User One'; userPrincipalName = 'one@contoso.com' }) }
        }
        Mock New-GraphBulkRequest { @([pscustomobject]@{ id = 'partner-tenant'; body = [pscustomobject]@{ displayName = 'Partner Inc' } }) }
    }

    It 'labels a principal from another tenant with that tenant, and leaves the rest alone' {
        $Rows = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com'

        $Foreign = $Rows | Where-Object PrincipalId -EQ 'gdap-group'
        $Foreign.PrincipalType | Should -Be 'Foreign (likely GDAP)'
        $Foreign.PrincipalTenantId | Should -Be 'partner-tenant'
        $Foreign.PrincipalDisplayName | Should -Be 'Partner Inc'

        ($Rows | Where-Object PrincipalId -EQ 'user-1').PrincipalType | Should -Be 'User'
        $Gone = $Rows | Where-Object PrincipalId -EQ 'deleted-user'
        $Gone.PrincipalType | Should -Be 'Unknown'
        $Gone.PrincipalTenantId | Should -BeNullOrEmpty
    }

    It 'shows the group name for a group in a partner tenant CIPP runs as' {
        Mock Get-CIPPPartnerTenantList { [pscustomobject]@{ partnerTenantId = 'partner-tenant' } }
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'gdap-group'; displayName = 'M365 GDAP Global Reader' }) }
        } -ParameterFilter { $tenantid -eq 'partner-tenant' }

        $Foreign = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com' | Where-Object PrincipalId -EQ 'gdap-group'

        $Foreign.PrincipalType | Should -Be 'Partner (GDAP)'
        $Foreign.PrincipalDisplayName | Should -Be 'M365 GDAP Global Reader (Partner Inc)'
    }

    It 'falls back to the tenant id when the tenant name lookup fails' {
        Mock New-GraphBulkRequest { throw 'Response status code does not indicate success: 400' }

        $Foreign = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com' | Where-Object PrincipalId -EQ 'gdap-group'

        $Foreign.PrincipalType | Should -Be 'Foreign (likely GDAP)'
        $Foreign.PrincipalDisplayName | Should -Be 'partner-tenant'
    }

    It 'never reads the directory of a tenant CIPP does not run as' {
        $null = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com'

        Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $tenantid -eq 'partner-tenant' }
    }

    It 'looks tenant names up as the partner tenant, not as the customer' {
        $null = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com'

        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 0 -ParameterFilter { $tenantid -eq 'contoso.com' }
    }

    It 'labels nothing when the tenant has no known id, so its own principals are not called foreign' {
        Mock Get-Tenants { $null }

        $Rows = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com'

        ($Rows | Where-Object PrincipalId -In 'gdap-group', 'deleted-user').PrincipalType | Should -Be @('Unknown', 'Unknown')
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'labels foreign principals on a PIM-licensed tenant from the unified assignment list' {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*roleEligibilitySchedules*' }
        # $expand=principal comes back empty for a principal that lives elsewhere.
        Mock New-GraphGetRequest {
            [pscustomobject]@{ principalId = 'gdap-group'; roleDefinitionId = 'role-1'; directoryScopeId = '/'; assignmentType = 'Assigned'; memberType = 'Direct' }
        } -ParameterFilter { $uri -like '*roleAssignmentScheduleInstances*' }

        $Foreign = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com' | Where-Object PrincipalId -EQ 'gdap-group'

        $Foreign.PrincipalType | Should -Be 'Foreign (likely GDAP)'
        $Foreign.PrincipalDisplayName | Should -Be 'Partner Inc'
        $Foreign.PIMCapable | Should -BeTrue
    }

    It 'reads what the cache writer stored, with no Graph or tenant lookups' {
        Mock New-CIPPDbRequest { @() }
        Mock New-CIPPDbRequest {
            @(
                [pscustomobject]@{ id = 'a1'; principalId = 'gdap-group'; roleDefinitionId = 'role-1'; directoryScopeId = '/'; foreignPrincipal = [pscustomobject]@{ TenantId = 'partner-tenant'; Type = 'Partner (GDAP)'; Name = 'M365 GDAP Global Reader (Partner Inc)' } }
                [pscustomobject]@{ id = 'a2'; principalId = 'deleted-user'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
            )
        } -ParameterFilter { $Type -eq 'RoleAssignments' }

        $Rows = Get-CIPPPIMRoleAssignments -TenantFilter 'contoso.com' -FromCache

        $Foreign = $Rows | Where-Object PrincipalId -EQ 'gdap-group'
        $Foreign.PrincipalType | Should -Be 'Partner (GDAP)'
        $Foreign.PrincipalTenantId | Should -Be 'partner-tenant'
        $Foreign.PrincipalDisplayName | Should -Be 'M365 GDAP Global Reader (Partner Inc)'
        ($Rows | Where-Object PrincipalId -EQ 'deleted-user').PrincipalType | Should -Be 'Unknown'

        # The non-PIM branch already loaded the assignments; they are not read a second time.
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $Type -eq 'RoleAssignments' }
        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke New-GraphBulkRequest -Times 0
        Should -Invoke Get-Tenants -Times 0
        Should -Invoke Get-CIPPPartnerTenantList -Times 0
    }
}
