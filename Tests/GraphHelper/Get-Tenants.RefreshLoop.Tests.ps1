# Get-Tenants is the only writer of the Tenants cache, and its refresh loop decides when a cached
# row is trusted as-is and when its domains are re-read from Graph. These pin the rules that were
# found broken in the field: a healthy row's default domain was never re-derived (a custom domain
# made default after onboarding stayed .onmicrosoft.com for months), a refresh scoped to one
# tenant was defeated by a matching Alias, the by-domain form of that refresh matched no
# relationships at all, and a transient failure of the domains read could overwrite a good custom
# default with the fallback's initial domain.

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
    $script:GuidB = '22222222-2222-2222-2222-222222222222'

    # LastRefresh is a [DateTimeOffset] here on purpose - that is what the table hands back, and
    # the staleness check must cope with it (a [datetime] cast of it throws).
    function New-CachedRow {
        param($Guid, $DisplayName, $Default, $Initial, $LastRefresh)
        [PSCustomObject]@{
            PartitionKey             = 'Tenants'
            RowKey                   = $Guid
            customerId               = $Guid
            displayName              = $DisplayName
            defaultDomainName        = $Default
            initialDomainName        = $Initial
            delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
            Excluded                 = $false
            GraphErrorCount          = 0
            LastGraphError           = ''
            RequiresRefresh          = $false
            LastRefresh              = $LastRefresh
        }
    }
    function New-Relationship {
        param($Guid, $DisplayName)
        [PSCustomObject]@{
            displayName        = "GDAP-$DisplayName"
            customer           = [PSCustomObject]@{ tenantId = $Guid; displayName = $DisplayName }
            autoExtendDuration = 'P180D'
            endDateTime        = (Get-Date).AddYears(1).ToString('o')
        }
    }
    function New-Domain {
        param($Id, [bool]$IsDefault, [bool]$IsInitial)
        [PSCustomObject]@{ id = $Id; isDefault = $IsDefault; isInitial = $IsInitial }
    }
}

AfterAll {
    $env:RefreshToken = $script:OrigRefreshToken
    $env:TenantID = $script:OrigTenantID
}

Describe 'Get-Tenants refresh loop' {
    BeforeEach {
        $script:RowsByKey = @{}
        $script:Relationships = @()
        $script:Aliases = @{}
        $script:DomainsByTenant = @{}
        $script:ThrowDomainsFor = @()
        $script:FallbackDomain = 'fallback.onmicrosoft.com'

        Mock Get-CippTable { @{} }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-AzDataTableEntity {
            if ($Filter -match "PartitionKey eq '([^']+)'" -and $script:Aliases.ContainsKey($Matches[1])) {
                return [PSCustomObject]@{ Value = $script:Aliases[$Matches[1]] }
            }
            $null
        }
        Mock Get-CIPPAzDataTableEntity {
            if ([string]::IsNullOrEmpty($Filter)) { return [PSCustomObject]@{ state = 'gdap' } }   # tenantMode
            if ($Filter -like '*Excluded eq true*') { return $null }                                  # skip list
            if ($Filter -match "RowKey eq '([^']+)'") { return $script:RowsByKey[$Matches[1]] }       # one tenant
            return @($script:RowsByKey.Values)                                                         # cache read
        }
        Mock New-GraphGetRequest {
            if ($uri -like '*delegatedAdminRelationships*') { return $script:Relationships }
            if ($uri -like '*beta/domains*') {
                if ($script:ThrowDomainsFor -contains $tenantid) { throw 'domains read failed' }
                return $script:DomainsByTenant[$tenantid]
            }
            if ($uri -like '*findTenantInformationByTenantId*') { return [PSCustomObject]@{ defaultDomainName = $script:FallbackDomain } }
            throw "unexpected Graph call: $uri"
        }
    }

    Context 'bulk refresh (no TenantFilter)' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:DomainsByTenant[$script:GuidA] = @(
                (New-Domain -Id 'contoso.com' -IsDefault $true -IsInitial $false),
                (New-Domain -Id 'contoso.onmicrosoft.com' -IsDefault $false -IsInitial $true)
            )
        }

        It 'trusts a fresh healthy row and does not re-read its domains' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-2))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*beta/domains*' } -Times 0 -Exactly
            @($Result).Count | Should -Be 1
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 're-reads domains for a row last derived over 7 days ago and picks up the new default' {
            # Cached while .onmicrosoft.com was still the default; a custom domain has since been made default in M365.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*beta/domains*' } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
            $Result.RequiresRefresh | Should -BeFalse
            $Result.LastRefresh | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddMinutes(-1)
        }

        It 'treats a row with no LastRefresh as stale' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh $null

            $null = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*beta/domains*' } -Times 1 -Exactly
        }

        It "does not let one tenant's fallback flag the next tenant for refresh" {
            $script:Relationships = @(
                (New-Relationship -Guid $script:GuidA -DisplayName 'Contoso'),
                (New-Relationship -Guid $script:GuidB -DisplayName 'Fabrikam')
            )
            $Stale = [DateTimeOffset]::UtcNow.AddDays(-30)
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh $Stale
            $script:RowsByKey[$script:GuidB] = New-CachedRow -Guid $script:GuidB -DisplayName 'Fabrikam' -Default 'fabrikam.onmicrosoft.com' -Initial 'fabrikam.onmicrosoft.com' -LastRefresh $Stale
            $script:DomainsByTenant[$script:GuidB] = @(
                (New-Domain -Id 'fabrikam.com' -IsDefault $true -IsInitial $false),
                (New-Domain -Id 'fabrikam.onmicrosoft.com' -IsDefault $false -IsInitial $true)
            )
            $script:ThrowDomainsFor = @($script:GuidA)

            $null = Get-Tenants -IncludeAll -TriggerRefresh

            # A fell back and is flagged; B read fine and must not inherit the flag.
            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.customerId -eq $script:GuidA -and $Entity.RequiresRefresh -eq $true } -Times 1 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.customerId -eq $script:GuidB -and $Entity.defaultDomainName -eq 'fabrikam.com' -and $Entity.RequiresRefresh -eq $false } -Times 1 -Exactly
        }
    }

    Context 'refresh scoped to one tenant' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:DomainsByTenant[$script:GuidA] = @(
                (New-Domain -Id 'contoso.com' -IsDefault $true -IsInitial $false),
                (New-Domain -Id 'contoso.onmicrosoft.com' -IsDefault $false -IsInitial $true)
            )
            # Fresh and healthy: only the scoping should force the re-read.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-2))
        }

        It 're-reads domains even when the tenant alias matches its display name' {
            $script:Aliases[$script:GuidA] = 'Contoso'

            $Result = Get-Tenants -TriggerRefresh -TenantFilter $script:GuidA

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*beta/domains*' } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 'resolves a domain filter to the customerId and scopes the relationship pull to it' {
            $Result = Get-Tenants -TriggerRefresh -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*delegatedAdminRelationships*' -and $uri -like "*customer/tenantId eq '$($script:GuidA)'*" } -Times 1 -Exactly
            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*beta/domains*' } -Times 1 -Exactly
            @($Result).Count | Should -Be 1
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }
    }

    Context 'when the domains read fails' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:ThrowDomainsFor = @($script:GuidA)
            $script:FallbackDomain = 'contoso.onmicrosoft.com'
        }

        It "keeps a cached custom default over the fallback's initial domain and flags the row for retry" {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.RequiresRefresh -eq $true -and $Entity.defaultDomainName -eq 'contoso.com' -and $Entity.initialDomainName -eq 'contoso.onmicrosoft.com' } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 'takes the fallback value when there is no custom default to protect' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.RequiresRefresh -eq $true -and $Entity.defaultDomainName -eq 'contoso.onmicrosoft.com' } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.onmicrosoft.com'
        }
    }
}
