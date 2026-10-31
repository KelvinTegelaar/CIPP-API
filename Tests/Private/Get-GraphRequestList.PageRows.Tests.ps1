# An AllTenants cache stores each tenant as page rows ('<tenant>|00001'...) written as Graph returns them, then a
# head row ('<tenant>', Pages = n) written last. A tenant is served once its head exists and all n pages are present,
# head then pages in order. Pages without a head while no run is filling the cache are a tenant that never finished
# and are served as a failed status; while a run is going they stay pending and the run's queue id is returned.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPQueueData { param($Reference) }
    function Get-StringHash { param($String) }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Test-CIPPGraphEndpointBlocked { param($Uri, $Expand, [switch]$Throw) }

    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')

    function Set-FakeRows {
        param([hashtable]$Rows)
        $script:Store = $Rows
    }

    # Key scans return keys and Pages; span fetches return the rows inside the RowKey range; full reads return all rows.
    function Get-FakeRows {
        param($Filter, $Property)
        $Keys = [string[]]@($script:Store.Keys)
        [System.Array]::Sort($Keys, [System.Collections.IComparer][StringComparer]::Ordinal)
        if ($Filter -match "RowKey ge '([^']*)' and RowKey le '([^']*)~'") {
            $From = $Matches[1]; $To = $Matches[2] + '~'
            $Keys = @($Keys | Where-Object { [string]::CompareOrdinal($_, $From) -ge 0 -and [string]::CompareOrdinal($_, $To) -le 0 })
        }
        foreach ($Key in $Keys) {
            $Row = $script:Store[$Key]
            if ($Property) {
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = $Key; Pages = $Row.Pages }
                # a row split for size comes back from a key scan as its physical part rows too
                for ($Part = 1; $Part -le [int]$Row.Parts; $Part++) { [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = "$Key-part$Part" } }
            } else {
                $script:FetchedKeys.Add($Key)
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = $Key; Pages = $Row.Pages; Data = $Row.Data }
            }
        }
    }

    function Get-Ids($Json) { @(($Json | ConvertFrom-Json) | ForEach-Object { $_.id ?? "$($_.Tenant):$($_.CippStatus)" }) }
}

Describe 'Get-GraphRequestList AllTenants cache page rows' {
    BeforeEach {
        $script:FetchedKeys = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName Get-StringHash -MockWith { 'PKHASH' }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPQueueData -MockWith { $null }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { @('a.com', 'b.com' | ForEach-Object { [PSCustomObject]@{ defaultDomainName = $_ } }) }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { Get-FakeRows -Filter $Filter -Property $Property }
    }

    It 'serves a tenant from its head and pages in page order, ignoring pages past its count' {
        Set-FakeRows @{
            'a.com'       = @{ Pages = 2; Data = '[]' }
            'a.com|00002' = @{ Data = '[{"id":"a3"}]' }
            'a.com|00001' = @{ Data = '[{"id":"a1"},{"id":"a2"}]' }
            'a.com|00003' = @{ Data = '[{"id":"orphan"}]' }
            'b.com'       = @{ Data = '[{"id":"b1"}]' }
        }
        $Status = @{}

        $Json = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -RawJsonArray -CacheStatus $Status

        Get-Ids $Json | Should -Be @('a1', 'a2', 'a3', 'b1')
        $Status.CachedTenants | Should -Be 2
    }

    It 'leaves out a tenant whose pages are not all there' {
        Set-FakeRows @{
            'a.com'       = @{ Pages = 2; Data = '[]' }
            'a.com|00001' = @{ Data = '[{"id":"a1"}]' }
            'b.com'       = @{ Pages = 0; Data = '[{"id":"b1"}]' }
        }
        $Status = @{}

        $Json = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -RawJsonArray -CacheStatus $Status

        Get-Ids $Json | Should -Be @('b1')
        $Status.CachedTenants | Should -Be 1
    }

    It 'serves a tenant that never finished as failed once no run is filling the cache' {
        Set-FakeRows @{
            'a.com'       = @{ Pages = 1; Data = '[]' }
            'a.com|00001' = @{ Data = '[{"id":"a1"}]' }
            'b.com|00001' = @{ Data = '[{"id":"b1"}]' }
        }
        $Status = @{}

        $Records = @(Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -CacheStatus $Status)

        @($Records | Where-Object id).id | Should -Be @('a1')
        ($Records | Where-Object Tenant -EQ 'b.com').CippStatus | Should -Be 'Could not finish loading this tenant. Reload it to try again.'
        $Status.CachedTenants | Should -Be 2
    }

    It 'keeps an unfinished tenant pending and returns the running queue while its run is going' {
        Mock -CommandName Get-CIPPQueueData -MockWith { [PSCustomObject]@{ QueueId = 'running-queue'; Status = 'Running'; Reference = 'AllTenants-PKHASH' } }
        Set-FakeRows @{
            'a.com'       = @{ Pages = 1; Data = '[]' }
            'a.com|00001' = @{ Data = '[{"id":"a1"}]' }
            'b.com|00001' = @{ Data = '[{"id":"b1"}]' }
        }
        $Status = @{}

        $Json = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -RawJsonArray -CacheStatus $Status

        Get-Ids $Json | Should -Be @('a1')
        $Status.CachedTenants | Should -Be 1
        $Status.QueueId | Should -Be 'running-queue'
        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'pages through a large tenant row by row and resumes inside it' {
        $Pad = 'x' * 150000
        Set-FakeRows @{
            'a.com'       = @{ Pages = 3; Data = '[]' }
            'a.com|00001' = @{ Data = "[{`"id`":`"a1`",`"p`":`"$Pad`"}]" }
            'a.com|00002' = @{ Data = "[{`"id`":`"a2`",`"p`":`"$Pad`"}]" }
            'a.com|00003' = @{ Data = "[{`"id`":`"a3`",`"p`":`"$Pad`"}]" }
            'b.com|00001' = @{ Data = '[{"id":"never-finished"}]' }
        }

        $First = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -MaxPageBytes 262144
        $Second = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -MaxPageBytes 262144 -nextLink $First.CippNextLink

        Get-Ids $First.CippPagedJson | Should -Be @('a1', 'a2')
        $First.CippNextLink | Should -Be 'a.com|00002'
        Get-Ids $Second.CippPagedJson | Should -Be @('a3', 'b.com:Could not finish loading this tenant. Reload it to try again.')
        $Second.CippNextLink | Should -BeNullOrEmpty
    }

    It 'fetches only the rows it serves, even when a span ends on a head row' {
        $Pad = 'x' * 150000
        Set-FakeRows @{
            'a.com'       = @{ Pages = 3; Data = '[]' }
            'a.com|00001' = @{ Parts = 4; Data = "[{`"id`":`"a1`",`"p`":`"$Pad`"}]" }
            'a.com|00002' = @{ Parts = 4; Data = "[{`"id`":`"a2`",`"p`":`"$Pad`"}]" }
            'a.com|00003' = @{ Parts = 4; Data = "[{`"id`":`"a3`",`"p`":`"$Pad`"}]" }
        }

        $First = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -MaxPageBytes 262144

        Get-Ids $First.CippPagedJson | Should -Be @('a1', 'a2')
        $script:FetchedKeys | Should -Not -Contain 'a.com|00003'
    }
}
