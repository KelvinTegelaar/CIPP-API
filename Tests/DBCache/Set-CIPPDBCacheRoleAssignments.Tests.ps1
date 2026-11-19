# Pester tests for Set-CIPPDBCacheRoleAssignments.
#
# Cached and AllTenants role views read foreign principals (partner GDAP groups) straight from the
# cache, so the writer has to store their classification and name next to each assignment.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-CIPPForeignPrincipalInfo { param($TenantFilter, $Assignments) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheRoleAssignments.ps1')
}

Describe 'Set-CIPPDBCacheRoleAssignments' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock New-GraphBulkRequest { @() }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ value = @() } }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'a1'; principalId = 'gdap-group'; principalOrganizationId = 'partner-tenant'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
                [pscustomobject]@{ id = 'a2'; principalId = 'user-1'; principalOrganizationId = 'home-tenant'; roleDefinitionId = 'role-1'; directoryScopeId = '/' }
            )
        }
        $script:Written = $null
        Mock Add-CIPPDbItem { $script:Written = @($Data) }
    }

    It 'stores the owning tenant and the resolved foreign principal with each assignment' {
        Mock Get-CIPPForeignPrincipalInfo { @{ 'gdap-group' = [pscustomobject]@{ TenantId = 'partner-tenant'; Type = 'Partner (GDAP)'; Name = 'M365 GDAP Global Reader (Partner Inc)' } } }

        Set-CIPPDBCacheRoleAssignments -TenantFilter 'contoso.com'

        $Group = $script:Written | Where-Object principalId -EQ 'gdap-group'
        $Group.principalOrganizationId | Should -Be 'partner-tenant'
        $Group.foreignPrincipal.Type | Should -Be 'Partner (GDAP)'
        $Group.foreignPrincipal.Name | Should -Be 'M365 GDAP Global Reader (Partner Inc)'
        ($script:Written | Where-Object principalId -EQ 'user-1').foreignPrincipal | Should -BeNullOrEmpty
    }

    It 'still caches the assignments when the foreign principal lookup fails' {
        Mock Get-CIPPForeignPrincipalInfo { throw 'Graph unavailable' }

        Set-CIPPDBCacheRoleAssignments -TenantFilter 'contoso.com'

        @($script:Written).Count | Should -Be 2
    }
}
