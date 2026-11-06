# Get-Tenants is the only writer of the Tenants cache, and its refresh loop decides when a cached
# row is trusted as-is and when its domains are re-read from Graph. These pin the rules that were
# found broken in the field: a healthy row's default domain was never re-derived (a custom domain
# made default after onboarding stayed .onmicrosoft.com for months), a refresh scoped to one
# tenant was defeated by a matching Alias, the by-domain form of that refresh matched no
# relationships at all, and a transient failure of the domains read could overwrite a good custom
# default with the fallback's initial domain.
#
# The multi-partner build never reads beta/domains inline: a row that needs its domains re-read
# goes through the batched findTenantInformationByTenantId lookup as its owning partner, is written
# back provisional (RequiresRefresh) and the authoritative read is queued to Push-UpdateTenantDomains.
# "Re-read" below therefore means the batched lookup ran and hydration was queued.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $Version) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-CIPPPartnerTenant { param($PartnerTenantId) }
    function Get-CIPPFeatureFlag { param($Id) }
    function Clear-CippTokenCache { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData, $headers, $level) }
    function Get-CippException { param($Exception) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Private/New-CIPPTenantRow.ps1')
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
    # Rows are written in one batch, so match inside the entity array rather than on the call.
    function Test-WrittenRow {
        param($Entity, [scriptblock]$Match)
        @(@($Entity) | Where-Object $Match).Count -eq 1
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
        $script:LookupByTenant = @{}        # default domain the batched lookup returns per tenant
        $script:LookupFailsFor = @()         # tenants the batched lookup returns nothing for
        $script:FallbackDomain = 'fallback.onmicrosoft.com'

        Mock Get-CippTable { @{} }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{} }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Start-CIPPOrchestrator {}
        Mock Clear-CippTokenCache {}
        Mock Get-CIPPFeatureFlag { [PSCustomObject]@{ Id = $Id; Enabled = $false } }
        Mock Get-CIPPPartnerTenant { @([PSCustomObject]@{ RowKey = $env:TenantID; IsPrimary = $true; Managed = $true }) }
        Mock Get-AzDataTableEntity {
            # Aliases are bulk-read once per build.
            if ($Filter -like "*RowKey eq 'Alias'*") {
                return @($script:Aliases.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ PartitionKey = $_.Key; RowKey = 'Alias'; Value = $_.Value } })
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
            throw "unexpected Graph call: $uri"
        }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                if ($script:LookupFailsFor -contains $Request.id) { continue }
                $Domain = if ($script:LookupByTenant.ContainsKey($Request.id)) { $script:LookupByTenant[$Request.id] } else { $script:FallbackDomain }
                [PSCustomObject]@{ id = $Request.id; status = 200; body = [PSCustomObject]@{ defaultDomainName = $Domain } }
            }
        }
    }

    Context 'default cache read' {
        It 'does not hide tenants behind an error-count threshold' {
            # The count is never reset for direct tenants, so a threshold filter drops them for good.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow)

            $Result = Get-Tenants

            Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like '*GraphErrorCount*' } -Times 0 -Exactly
            $Result.customerId | Should -Be $script:GuidA
        }
    }

    Context 'bulk refresh (no TenantFilter)' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:LookupByTenant[$script:GuidA] = 'contoso.com'
        }

        It 'trusts a fresh healthy row and does not re-read its domains' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-2))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
            @($Result).Count | Should -Be 1
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 're-reads domains for a row last derived over 7 days ago and picks up the new default' {
            # Cached while .onmicrosoft.com was still the default; a custom domain has since been made default in M365.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
            # Provisional until Push-UpdateTenantDomains confirms it - and that hydration must be queued.
            $Result.RequiresRefresh | Should -BeTrue
            Should -Invoke Start-CIPPOrchestrator -ParameterFilter { $InputObject.Batch.customerId -contains $script:GuidA } -Times 1 -Exactly
            $Result.LastRefresh | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddMinutes(-1)
        }

        It 'treats a row with no LastRefresh as stale' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh $null

            $null = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        }

        It "does not let one tenant's failed lookup affect the next tenant" {
            $script:Relationships = @(
                (New-Relationship -Guid $script:GuidA -DisplayName 'Contoso'),
                (New-Relationship -Guid $script:GuidB -DisplayName 'Fabrikam')
            )
            $Stale = [DateTimeOffset]::UtcNow.AddDays(-30)
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh $Stale
            $script:RowsByKey[$script:GuidB] = New-CachedRow -Guid $script:GuidB -DisplayName 'Fabrikam' -Default 'fabrikam.onmicrosoft.com' -Initial 'fabrikam.onmicrosoft.com' -LastRefresh $Stale
            $script:LookupByTenant[$script:GuidB] = 'fabrikam.com'
            $script:LookupFailsFor = @($script:GuidA)

            $null = Get-Tenants -IncludeAll -TriggerRefresh

            # A has nothing usable and is skipped; B resolves and is written with its own result.
            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { Test-WrittenRow $Entity { $_.customerId -eq $script:GuidA } } -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { Test-WrittenRow $Entity { $_.customerId -eq $script:GuidB -and $_.defaultDomainName -eq 'fabrikam.com' } } -Times 1 -Exactly
        }
    }

    Context 'refresh scoped to one tenant' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:LookupByTenant[$script:GuidA] = 'contoso.com'
            # Fresh and healthy: only the scoping should force the re-read.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-2))
        }

        It 're-reads domains even when the tenant alias matches its display name' {
            $script:Aliases[$script:GuidA] = 'Contoso'

            $Result = Get-Tenants -TriggerRefresh -TenantFilter $script:GuidA

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 'resolves a domain filter to the customerId and scopes the relationship pull to it' {
            $Result = Get-Tenants -TriggerRefresh -TenantFilter 'contoso.onmicrosoft.com'

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*delegatedAdminRelationships*' -and $uri -like "*customer/tenantId eq '$($script:GuidA)'*" } -Times 1 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
            @($Result).Count | Should -Be 1
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }
    }

    Context 'when the lookup returns the initial domain or nothing' {
        BeforeEach {
            $script:Relationships = @(New-Relationship -Guid $script:GuidA -DisplayName 'Contoso')
            $script:FallbackDomain = 'contoso.onmicrosoft.com'
        }

        It "keeps a cached custom default over the lookup's initial domain and flags the row for retry" {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { Test-WrittenRow $Entity { $_.RequiresRefresh -eq $true -and $_.defaultDomainName -eq 'contoso.com' -and $_.initialDomainName -eq 'contoso.onmicrosoft.com' } } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 'keeps a cached custom default even when the lookup returns nothing' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))
            $script:LookupFailsFor = @($script:GuidA)

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { Test-WrittenRow $Entity { $_.RequiresRefresh -eq $true -and $_.defaultDomainName -eq 'contoso.com' } } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.com'
        }

        It 'takes the lookup value when there is no custom default to protect' {
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { Test-WrittenRow $Entity { $_.RequiresRefresh -eq $true -and $_.defaultDomainName -eq 'contoso.onmicrosoft.com' } } -Times 1 -Exactly
            $Result.defaultDomainName | Should -Be 'contoso.onmicrosoft.com'
        }

        It 'keeps a cached .onmicrosoft.com initial domain when the fallback returns a custom domain' {
            # A custom initial domain becomes delegatedOrg in the portal links and lands on a login prompt.
            $script:FallbackDomain = 'contoso.com'
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.onmicrosoft.com' -Initial 'contoso.onmicrosoft.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.RequiresRefresh -eq $true -and $Entity.defaultDomainName -eq 'contoso.com' -and $Entity.initialDomainName -eq 'contoso.onmicrosoft.com' } -Times 1 -Exactly
            $Result.initialDomainName | Should -Be 'contoso.onmicrosoft.com'
        }

        It 'replaces a cached custom initial domain with the fallback .onmicrosoft.com one' {
            # Rows written by the old fallback carry the custom default in initialDomainName.
            $script:RowsByKey[$script:GuidA] = New-CachedRow -Guid $script:GuidA -DisplayName 'Contoso' -Default 'contoso.com' -Initial 'contoso.com' -LastRefresh ([DateTimeOffset]::UtcNow.AddDays(-30))

            $Result = Get-Tenants -IncludeAll -TriggerRefresh

            Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.defaultDomainName -eq 'contoso.com' -and $Entity.initialDomainName -eq 'contoso.onmicrosoft.com' } -Times 1 -Exactly
            $Result.initialDomainName | Should -Be 'contoso.onmicrosoft.com'
        }
    }
}
