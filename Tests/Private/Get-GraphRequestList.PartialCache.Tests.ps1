# An AllTenants cache holds one row per tenant, so a tenant without a row has not finished. A partial cache
# must say so, re-attach to the run still filling it, and only queue more when asked: a cancelled run stays
# cancelled until the user loads the missing tenants or reloads them all.

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

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')

    function Invoke-Paged {
        param([hashtable]$Extra = @{})
        $script:Status = @{}
        Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -ManualPagination -RawJsonArray -CacheStatus $script:Status @Extra
    }
}

Describe 'Get-GraphRequestList partial AllTenants cache' {
    BeforeEach {
        Mock -CommandName Get-StringHash -MockWith { 'PKHASH' }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPQueueData -MockWith { $null }
        Mock -CommandName Get-Tenants -MockWith {
            @('a.com', 'b.com', 'c.com' | ForEach-Object { [PSCustomObject]@{ defaultDomainName = $_ } })
        }
        # b.com has no row: its task has not finished
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Property) {
                @('a.com', 'c.com' | ForEach-Object { [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = $_ } })
            } else {
                @([PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'a.com'; Data = '[{"id":"a1"}]' }
                    [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'c.com'; Data = '[{"id":"c1"}]' })
            }
        }
        Mock -CommandName New-CippQueueEntry -MockWith { @{ RowKey = 'new-queue' } }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { }
    }

    It 'serves the cached tenants and reports how many of all tenants they cover' {
        $Result = Invoke-Paged

        ($Result.CippPagedJson | ConvertFrom-Json).id | Should -Be @('a1', 'c1')
        $script:Status.CachedTenants | Should -Be 2
        $script:Status.ExpectedTenants | Should -Be 3
        $script:Status.QueueId | Should -BeNullOrEmpty
        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'points at the run still filling the cache, so a reloaded page tracks it again' {
        Mock -CommandName Get-CIPPQueueData -MockWith { [PSCustomObject]@{ RowKey = 'running-queue'; Status = 'Running'; Reference = 'AllTenants-PKHASH' } }

        $null = Invoke-Paged

        $script:Status.QueueId | Should -Be 'running-queue'
        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'queues only the missing tenants when asked to fill them' {
        $null = Invoke-Paged -Extra @{ FillMissing = $true }

        $script:Status.QueueId | Should -Be 'new-queue'
        Should -Invoke New-CippQueueEntry -Times 1 -ParameterFilter { $TotalTasks -eq 1 -and $Name -like '*1 missing tenants*' }
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter { @($InputObject.Batch.TenantFilter) -join ',' -eq 'b.com' }
    }

    It 'queues every tenant when asked to reload, while still serving the cached rows' {
        $Result = Invoke-Paged -Extra @{ RefreshCache = $true }

        ($Result.CippPagedJson | ConvertFrom-Json).id | Should -Be @('a1', 'c1')
        $script:Status.QueueId | Should -Be 'new-queue'
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter { @($InputObject.Batch.TenantFilter) -join ',' -eq 'a.com,b.com,c.com' }
    }

    It 'starts nothing while a run is already filling the cache' {
        Mock -CommandName Get-CIPPQueueData -MockWith { [PSCustomObject]@{ RowKey = 'running-queue'; Status = 'Running'; Reference = 'AllTenants-PKHASH' } }

        $null = Invoke-Paged -Extra @{ RefreshCache = $true }

        $script:Status.QueueId | Should -Be 'running-queue'
        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'ignores the flags on a page continuation, which repeats them' {
        $null = Invoke-Paged -Extra @{ FillMissing = $true; nextLink = 'a.com' }
        $null = Invoke-Paged -Extra @{ RefreshCache = $true; nextLink = 'a.com' }

        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'counts a split tenant once on the unpaged path' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'a.com'; Data = '[{"id":"a1"}]' }
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'b.com'; OriginalEntityId = 'b.com'; Data = '[{"id":"b1"}]' }
                [PSCustomObject]@{ PartitionKey = 'PKHASH'; RowKey = 'c.com'; Data = '[{"id":"c1"}]' })
        }
        $Status = @{}

        $null = Get-GraphRequestList -TenantFilter 'AllTenants' -Endpoint 'users' -RawJsonArray -CacheStatus $Status

        $Status.CachedTenants | Should -Be 3
        $Status.ExpectedTenants | Should -Be 3
    }
}
