# Integration tests for Set-CIPPDBCacheDefenderCVEs against the real Add-CIPPDbItem.
#
# The collector streams rows into a single Add-CIPPDbItem pipeline on purpose. Add-CIPPDbItem
# runs its orphan cleanup and writes DefenderCVEs-Count once per pipeline, in its end block,
# keyed to the run id minted in its begin block. Splitting the flush across several calls
# would give each chunk its own run id, so each later call's cleanup would treat earlier
# chunks' rows as orphans once the run exceeded the skew margin, and would leave the stored
# count equal to the final chunk. These tests fail if anyone reintroduces a per-chunk flush.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $CollectorPath = Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDefenderCVEs.ps1'
    $DbItemPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPDbItem.ps1'

    # -Force MUST be declared [switch] here: without it the real call sites' trailing -Force
    # binds no argument and the resulting error is swallowed by the collector's own catch.
    function Get-DefenderTvmRaw { param($TenantId, [int]$MaxPages, [switch]$Stream) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippTable { param($tablename) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [switch]$CreateTableIfNotExists) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . $DbItemPath
    . $CollectorPath

    function New-TvmRecord {
        param($cveId, $deviceId)
        [pscustomobject]@{
            cveId                      = $cveId
            deviceId                   = $deviceId
            deviceName                 = "PC-$deviceId"
            osVersion                  = '10.0.19045'
            softwareVendor             = 'microsoft'
            softwareName               = 'edge'
            softwareVersion            = '120.0.0'
            vulnerabilitySeverityLevel = 'High'
            exploitabilityLevel        = 'ExploitIsPublic'
        }
    }
}

Describe 'Set-CIPPDBCacheDefenderCVEs flush semantics' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()

        # Select batches with an explicit loop, not Where-Object: a pipeline that matches a
        # single batch collapses it, so indexing [0] would reach into the batch instead of
        # selecting it.
        function Get-DataBatches {
            $Result = [System.Collections.Generic.List[object]]::new()
            foreach ($Write in $script:Writes) {
                if ($Write[0].RowKey -notlike '*-Count') { $Result.Add($Write) }
            }
            # ,$Result — a bare return would unroll the list and, for a single batch,
            # hand back the batch array itself.
            return , $Result
        }

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { $script:Removed.AddRange(@($Entity)) }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Writes.Add(@($Entity)) }
    }

    It 'runs the orphan cleanup exactly once for the whole run' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith {
            foreach ($i in 1..250) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
        }

        Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

        # One cleanup query means one Add-CIPPDbItem pipeline. Per-chunk flushing would
        # show one query per chunk.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'flushes in batches of 100 while the producer is still emitting' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith {
            foreach ($i in 1..250) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
        }

        Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

        $Batches = Get-DataBatches
        $Batches.Count | Should -Be 3
        $Batches[0].Count | Should -Be 100
        $Batches[1].Count | Should -Be 100
        $Batches[2].Count | Should -Be 50
    }

    It 'writes DefenderCVEs-Count once with the run total, not the final chunk' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith {
            foreach ($i in 1..250) { New-TvmRecord -cveId "CVE-$i" -deviceId "d$i" }
        }

        Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

        $CountRows = $script:Writes | ForEach-Object { $_ } | Where-Object { $_.RowKey -eq 'DefenderCVEs-Count' }
        @($CountRows).Count | Should -Be 1
        $CountRows.DataCount | Should -Be 250
        $CountRows.PartitionKey | Should -Be $script:Tenant
    }

    It 'stores each row under the tenant partition with the CVE payload in Data' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith {
            New-TvmRecord -cveId 'CVE-2024-0001' -deviceId 'd1'
            New-TvmRecord -cveId 'CVE-2024-0001' -deviceId 'd2'
        }

        Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

        $Batches = Get-DataBatches
        $Batches.Count | Should -Be 1
        $Batch = $Batches[0]
        $Batch.Count | Should -Be 1
        $Batch[0].PartitionKey | Should -Be $script:Tenant
        $Batch[0].Type | Should -Be 'DefenderCVEs'
        # Stable, idempotent RowKey derived from the CVE id (was a random GUID per run).
        $Batch[0].RowKey | Should -Be 'DefenderCVEs-CVE-2024-0001'

        # Get-CIPPCVEReport reads these fields off the deserialised Data blob.
        $Payload = $Batch[0].Data | ConvertFrom-Json
        $Payload.PartitionKey | Should -Be 'CVE-2024-0001'
        $Payload.customerId | Should -Be $script:Tenant
        $Payload.deviceCount | Should -Be 2
        ($Payload.deviceDetailsJson | ConvertFrom-Json).deviceName | Should -Be @('PC-d1', 'PC-d2')
    }

    It 'deletes only rows left over from an earlier run, never rows this run wrote' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith { New-TvmRecord -cveId 'CVE-A' -deviceId 'd1' }
        # Feed one of this run's own writes back through the cleanup query alongside a
        # foreign row. The delete authority is the RunId stamped on every written row -
        # identity, not age - so however slow the run or however far the storage clock
        # drifts, only the foreign row may go.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            $OwnRows = foreach ($Write in $script:Writes) {
                foreach ($E in $Write) { if ($E.RowKey -notlike '*-Count') { $E } }
            }
            @([pscustomobject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'DefenderCVEs-from-earlier-run'; ETag = '*' }) + @($OwnRows)
        }

        Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant

        @($script:Removed).Count | Should -Be 1
        $script:Removed[0].RowKey | Should -Be 'DefenderCVEs-from-earlier-run'
    }

    It 'does not touch the table when the fetch faults mid-stream' {
        Mock -CommandName Get-DefenderTvmRaw -MockWith {
            New-TvmRecord -cveId 'CVE-A' -deviceId 'd1'
            throw 'page 3 failed'
        }

        { Set-CIPPDBCacheDefenderCVEs -TenantFilter $script:Tenant } | Should -Throw

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
