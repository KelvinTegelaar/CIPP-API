# The CleanOld branch removes tenants that dropped out of GDAP. It used to query GDAP
# relationships unconditionally and log a Critical error on an empty result, even when there
# were no GDAP-managed tenants on record to reconcile - always true for a direct-tenant
# deployment, so it logged a false Critical every run of the nightly cleanup timer.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData, $headers, $level) }
    function Get-CippException { param($Exception) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-Tenants.ps1')

    $script:OrigRefreshToken = $env:RefreshToken
    $script:OrigTenantID = $env:TenantID
    $env:RefreshToken = 'pester'
    $env:TenantID = 'ffffffff-ffff-ffff-ffff-ffffffffffff'

    $script:GuidA = '11111111-1111-1111-1111-111111111111'
}

AfterAll {
    $env:RefreshToken = $script:OrigRefreshToken
    $env:TenantID = $script:OrigTenantID
}

Describe 'Get-Tenants -CleanOld' {
    BeforeEach {
        # 'owntenant' and a non-empty cache read keep the unrelated GDAP-refresh and
        # owntenant-fallback blocks out of the way, so only the CleanOld branch is exercised.
        $script:GdapManagedTenants = @()
        $script:GDAPRelationships = @()

        Mock Get-CippTable { @{} }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity {
            if ([string]::IsNullOrEmpty($Filter)) { return [PSCustomObject]@{ state = 'owntenant' } }             # tenantMode
            if ($Filter -like '*Excluded eq true*') { return $null }                                              # skip list
            if ($Filter -like '*delegatedPrivilegeStatus ne*') { return $script:GdapManagedTenants }              # CleanOld's own read
            return @([PSCustomObject]@{ RowKey = $script:GuidA; customerId = $script:GuidA; displayName = 'Contoso'; defaultDomainName = 'contoso.com' })
        }
        Mock New-GraphGetRequest {
            if ($uri -like '*delegatedAdminRelationships*') { return $script:GDAPRelationships }
            throw "unexpected Graph call: $uri"
        }
    }

    It 'does not query GDAP relationships when no GDAP-managed tenants are on record' {
        $script:GdapManagedTenants = @()

        Get-Tenants -CleanOld | Out-Null

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'removes a GDAP-managed tenant that dropped out of the relationships list' {
        $GuidB = '22222222-2222-2222-2222-222222222222'
        $script:GdapManagedTenants = @([PSCustomObject]@{ customerId = $GuidB })
        $script:GDAPRelationships = @()

        try { Get-Tenants -CleanOld | Out-Null } catch { }

        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*delegatedAdminRelationships*' } -Times 1 -Exactly
    }

    It 'still throws and logs Critical when GDAP-managed tenants exist but the relationships call comes back empty' {
        $GuidB = '22222222-2222-2222-2222-222222222222'
        $script:GdapManagedTenants = @([PSCustomObject]@{ customerId = $GuidB })
        $script:GDAPRelationships = @()

        { Get-Tenants -CleanOld } | Should -Throw

        # Once from the try block's own check, once more from the outer catch after the throw.
        Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Critical' } -Times 2 -Exactly
    }

    It 'removes tenants no longer present in an active GDAP relationships list' {
        $GuidB = '22222222-2222-2222-2222-222222222222'
        $GuidC = '33333333-3333-3333-3333-333333333333'
        $script:GdapManagedTenants = @(
            [PSCustomObject]@{ customerId = $GuidB },
            [PSCustomObject]@{ customerId = $GuidC }
        )
        $script:GDAPRelationships = @(
            [PSCustomObject]@{
                displayName        = 'GDAP-Fabrikam'
                customer           = [PSCustomObject]@{ tenantId = $GuidB; displayName = 'Fabrikam' }
                autoExtendDuration = 'P180D'
                endDateTime        = (Get-Date).AddYears(1).ToString('o')
            }
        )

        Get-Tenants -CleanOld | Out-Null

        Should -Invoke Remove-CIPPAzDataTableEntity -ParameterFilter { $Entity.customerId -eq $GuidC } -Times 1 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -ParameterFilter { $Entity.customerId -eq $GuidB } -Times 0 -Exactly
    }
}
