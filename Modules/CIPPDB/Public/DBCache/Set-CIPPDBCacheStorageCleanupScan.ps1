function Set-CIPPDBCacheStorageCleanupScan {
    <#
    .SYNOPSIS
        Fans out SharePoint storage cleanup signal collection, batched by site.

    .DESCRIPTION
        Enumerates every non-personal, non-system SharePoint site and starts a child orchestration
        with one activity per batch of 20 sites (Push-DBCacheStorageCleanupScanBatch). A single
        PostExecution (Push-StoreStorageCleanupScan) aggregates every batch and writes the
        StorageCleanupScan cache once.

        Hold-only / report-private: only the storage report reads this cache. It is not part of
        nightly CIPPDB collection and is not consumed by ListSites or other List APIs.

        Per site the batch collects library StorageMetrics (versionEstimateBytes) and an aggregate
        recycle-bin summary (sizes only — no item titles or paths).

    .PARAMETER TenantFilter
        The tenant to cache storage cleanup signals for

    .PARAMETER QueueId
        Optional queue ID for progress tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $BatchSize = 20
    $SitesToLeaveOut = @(
        'search'
        'contentTypeHub'
        'appcatalog'
        'portals/hub'
        'portals/community'
    )

    function Test-CIPPStorageCleanupLeaveOut {
        param(
            [string]$Name,
            [string]$WebUrl,
            [string[]]$LeaveOut
        )
        $SitePath = $null
        $SitePathLeaf = $null
        if (-not [string]::IsNullOrWhiteSpace($WebUrl)) {
            try {
                $SitePath = ([System.Uri]$WebUrl).AbsolutePath.Trim('/')
                if (-not [string]::IsNullOrWhiteSpace($SitePath)) {
                    $SitePathLeaf = $SitePath.Split('/')[-1]
                }
            } catch {
                $SitePath = $null
                $SitePathLeaf = $null
            }
        }
        foreach ($LeaveOutName in $LeaveOut) {
            if (
                ([string]::Equals($Name, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                ([string]::Equals($SitePath, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                ([string]::Equals($SitePathLeaf, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase))
            ) {
                return $true
            }
        }
        return $false
    }

    try {
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'StorageCleanupScanCache' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog
        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a SharePoint license, skipping StorageCleanupScan cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting StorageCleanupScan collection' -sev Debug

        $RawSites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true)

        $SiteById = @{}
        foreach ($Site in $RawSites) {
            if (-not $Site.id -or $Site.isPersonalSite) { continue }
            if (Test-CIPPStorageCleanupLeaveOut -Name $Site.name -WebUrl $Site.webUrl -LeaveOut $SitesToLeaveOut) { continue }
            $SiteById[$Site.id] = $Site
        }
        $Sites = @($SiteById.Values)
        $ExpectedSiteCount = $Sites.Count

        if ($ExpectedSiteCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No SharePoint sites found; writing empty StorageCleanupScan cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -Data @() -AddCount
            return
        }

        $Batches = [System.Collections.Generic.List[object]]::new()
        $TotalBatches = [Math]::Ceiling($Sites.Count / $BatchSize)
        for ($i = 0; $i -lt $Sites.Count; $i += $BatchSize) {
            $BatchSites = $Sites[$i..[Math]::Min($i + $BatchSize - 1, $Sites.Count - 1)]
            $BatchNumber = [Math]::Floor($i / $BatchSize) + 1
            $SiteSeeds = foreach ($Site in $BatchSites) {
                [PSCustomObject]@{
                    id          = $Site.id
                    webUrl      = $Site.webUrl
                    displayName = $Site.displayName ?? $Site.name
                }
            }
            $BatchItem = [PSCustomObject]@{
                FunctionName = 'DBCacheStorageCleanupScanBatch'
                TenantFilter = $TenantFilter
                QueueName    = "Storage Cleanup Scan Batch $BatchNumber/$TotalBatches - $TenantFilter"
                BatchNumber  = $BatchNumber
                TotalBatches = $TotalBatches
                Sites        = @($SiteSeeds)
            }
            if ($QueueId) {
                $BatchItem | Add-Member -NotePropertyName 'QueueId' -NotePropertyValue $QueueId -Force
            }
            [void]$Batches.Add($BatchItem)
        }

        if ($QueueId -and $Batches.Count -gt 0) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Batches.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with StorageCleanupScan batch tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $InputObject = [PSCustomObject]@{
            Batch            = @($Batches)
            OrchestratorName = "StorageCleanupScan_$TenantFilter"
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'StoreStorageCleanupScan'
                Parameters   = @{
                    TenantFilter      = $TenantFilter
                    ExpectedSiteCount = $ExpectedSiteCount
                }
            }
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started StorageCleanupScan collection across $ExpectedSiteCount sites in $($Batches.Count) batches" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start StorageCleanupScan collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
