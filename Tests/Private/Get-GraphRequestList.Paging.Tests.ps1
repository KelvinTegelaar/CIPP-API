# Pester tests for the paged AllTenants cache serve in Get-GraphRequestList
# Validates that ManualPagination + RawJsonArray serves pages bounded by the byte budget
# alone (never a tenant count), fetched as span range queries, with a continuation token;
# that the key scan never fetches Data payloads; that the queue fallback still triggers on
# a cold cache; and that the unpaged fast path is intact.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stub every CIPP helper the exercised paths call so Pester's Mock has a command to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPQueueData { param($Reference) }
    function Get-StringHash { param($String) }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function New-GraphGetRequest { param($uri, $tenantid) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')

    # Emulates a span fetch: blobs inside the [From, To] RowKey range in ordinal order.
    function Select-FakeBlobRows {
        param([string]$Filter)
        if ($Filter -notmatch "RowKey ge '([^']*)' and RowKey le '([^']*)~'") { return @() }
        $From = $Matches[1]
        $To = $Matches[2]
        $Keys = [string[]]@($script:TenantBlobs.Keys)
        [System.Array]::Sort($Keys, [System.Collections.IComparer][StringComparer]::Ordinal)
        @($Keys | Where-Object {
                [string]::CompareOrdinal($_, $From) -ge 0 -and [string]::CompareOrdinal($_, $To) -le 0
            } | ForEach-Object {
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = $_; Data = $script:TenantBlobs[$_] }
            })
    }
}

Describe 'Get-GraphRequestList paged AllTenants cache serve' {
    BeforeEach {
        Mock -CommandName Get-StringHash -MockWith { 'PKHASH' }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPQueueData -MockWith { $null }
        Mock -CommandName Get-Tenants -MockWith {
            @(
                [PSCustomObject]@{ defaultDomainName = 'a.com' }
                [PSCustomObject]@{ defaultDomainName = 'b.com' }
                [PSCustomObject]@{ defaultDomainName = 'c.com' }
            )
        }

        # Key scans (Property set) return raw physical rows incl. '-part<n>' rows and an
        # unmanaged tenant (b0gus.com) inside the span range; data fetches return blobs.
        $script:TenantBlobs = @{
            'a.com'     = '[{"id":"a1"},{"id":"a2"}]'
            'b.com'     = '[{"id":"b1"}]'
            'b0gus.com' = '[{"id":"bogus"}]'
            'c.com'     = '[{"id":"c1"}]'
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Property) {
                @(
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'a.com' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'b.com' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'b.com-part1' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'b.com-part2' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'b0gus.com' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'c.com' }
                )
            } else {
                Select-FakeBlobRows -Filter $Filter
            }
        }
    }

    It 'serves all managed tenants in one span when they fit, with valid JSON and no token' {
        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray

        $Result.PSObject.Properties.Name | Should -Contain 'CippPagedJson'
        $Result.CippNextLink | Should -BeNullOrEmpty
        $Parsed = $Result.CippPagedJson | ConvertFrom-Json
        # a.com's two rows plus one each from b.com and c.com. b0gus.com sits inside the
        # span's RowKey range but is unmanaged, so it must be dropped; the part rows
        # deduplicate into b.com's count.
        $Parsed | Should -HaveCount 4
        $Parsed.id | Should -Be @('a1', 'a2', 'b1', 'c1')
        # The key scan must project keys only - never Data payloads, and never a subset of
        # the split-entity markers (a partial marker projection makes the module fail
        # reassembly and drop split tenants from the plan entirely).
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $null -ne $Property -and $Property -notcontains 'OriginalEntityId' -and $Property -notcontains 'Data'
        }
        # One span covers all three tenants: exactly one range fetch.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "*RowKey ge*" }
    }

    It 'resumes after the tenant named by the incoming nextLink token' {
        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -nextLink 'a.com'

        $Parsed = $Result.CippPagedJson | ConvertFrom-Json
        $Parsed.id | Should -Be @('b1', 'c1')
        $Result.CippNextLink | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $Filter -like "*RowKey ge 'a.com'*" }
    }

    It 'ends the page on the character budget mid-span and resumes from the token' {
        # b.com's blob alone exceeds the 4M character budget. All three tenants share one
        # span, so the budget must end the page inside the span: c.com's fetched blob is
        # discarded and served by the next page.
        $script:TenantBlobs['b.com'] = '[{"id":"b1","pad":"' + ('x' * 4200000) + '"}]'

        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray

        $Result.CippNextLink | Should -Be 'b.com'
        $Ids = ($Result.CippPagedJson | ConvertFrom-Json).id
        $Ids | Should -Contain 'a1'
        $Ids | Should -Not -Contain 'c1'

        $Next = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -nextLink $Result.CippNextLink
        ($Next.CippPagedJson | ConvertFrom-Json).id | Should -Be @('c1')
        $Next.CippNextLink | Should -BeNullOrEmpty
    }

    It 'honours a MaxPageBytes override, clamped to the floor' {
        # a.com's ~300KB exceeds the 256KB floor that the 1-byte request clamps up to, so
        # the page ends after the first tenant even though all three share a span.
        $script:TenantBlobs['a.com'] = '[{"id":"a1","pad":"' + ('x' * 300000) + '"}]'

        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -MaxPageBytes 1

        $Result.CippNextLink | Should -Be 'a.com'
        $Next = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -MaxPageBytes 1 -nextLink $Result.CippNextLink
        ($Next.CippPagedJson | ConvertFrom-Json).id | Should -Be @('b1', 'c1')
        $Next.CippNextLink | Should -BeNullOrEmpty
    }

    It 'never re-serves earlier tenants on resume when tenant casing is mixed' {
        # Ordinal order puts 'CyberDrainDev.com' (uppercase C) before 'cipp.com'; a
        # culture-aware plan sort ordered them the other way round, so resuming after
        # CyberDrainDev re-served cipp's rows and the chain returned duplicates.
        Mock -CommandName Get-Tenants -MockWith {
            @(
                [PSCustomObject]@{ defaultDomainName = 'CyberDrainDev.com' }
                [PSCustomObject]@{ defaultDomainName = 'cipp.com' }
            )
        }
        $script:TenantBlobs = @{
            'CyberDrainDev.com' = '[{"id":"cdd1"}]'
            'cipp.com'          = '[{"id":"cipp1"}]'
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Property) {
                @(
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'cipp.com' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'CyberDrainDev.com' }
                )
            } else {
                Select-FakeBlobRows -Filter $Filter
            }
        }

        $Full = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray
        ($Full.CippPagedJson | ConvertFrom-Json).id | Should -Be @('cdd1', 'cipp1')

        $Resumed = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -nextLink 'CyberDrainDev.com'
        ($Resumed.CippPagedJson | ConvertFrom-Json).id | Should -Be @('cipp1')
    }

    It 'serves many small tenants in one page regardless of tenant count' {
        # The complaint span fetching answers: 60 tiny tenants must not need 60 requests
        # or 60 queries - they share spans and land in a single page.
        $script:ManyTenants = @(1..60 | ForEach-Object { 'tenant{0:D3}.example' -f $_ })
        Mock -CommandName Get-Tenants -MockWith {
            @($script:ManyTenants | ForEach-Object { [PSCustomObject]@{ defaultDomainName = $_ } })
        }
        $script:TenantBlobs = @{}
        foreach ($Tenant in $script:ManyTenants) { $script:TenantBlobs[$Tenant] = ('[{{"id":"{0}"}}]' -f $Tenant) }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Property) {
                @($script:ManyTenants | ForEach-Object { [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = $_ } })
            } else {
                Select-FakeBlobRows -Filter $Filter
            }
        }

        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray

        $Result.CippNextLink | Should -BeNullOrEmpty
        ($Result.CippPagedJson | ConvertFrom-Json) | Should -HaveCount 60
        # 60 one-row tenants at 40 rows per span: two range fetches, one page.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -ParameterFilter { $Filter -like "*RowKey ge*" }
    }

    It 'falls through to the queue flow when the cache is cold' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName New-CippQueueEntry -MockWith { @{ RowKey = 'queue-1' } }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { 'instance-1' }

        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray

        $Result.Queued | Should -BeTrue
        $Result.QueueId | Should -Be 'queue-1'
        Should -Invoke Start-CIPPOrchestrator -Times 1
    }

    It 'keeps the unpaged raw concat path when ManualPagination is not set' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'a.com'; OriginalEntityId = $null; Data = '[{"id":"a1"}]' }
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'c.com'; OriginalEntityId = $null; Data = '[{"id":"c1"}]' }
            )
        }

        $Result = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -RawJsonArray

        $Result | Should -BeOfType [string]
        ($Result | ConvertFrom-Json).id | Should -Be @('a1', 'c1')
    }
}
