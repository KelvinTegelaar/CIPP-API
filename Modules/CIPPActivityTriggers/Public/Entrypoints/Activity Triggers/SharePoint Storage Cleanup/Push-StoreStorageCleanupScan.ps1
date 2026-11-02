function Push-StoreStorageCleanupScan {
    <#
    .SYNOPSIS
        Post-execution function that aggregates per-batch storage cleanup rows and writes the cache.

    .DESCRIPTION
        Collects the Sites arrays returned by every Push-DBCacheStorageCleanupScanBatch activity,
        flattens their Site and Library rows into a single row set, and writes StorageCleanupScan
        once via Add-CIPPDbItem.

        Partial runs: a site that came back Skipped, or that no batch returned (ExpectedSiteIds), keeps
        its prior Site and Library rows, flagged Skipped. A run that collected nothing writes nothing.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $ExpectedSiteCount = [int]$Item.Parameters.ExpectedSiteCount
    $ExpectedSiteIds = @($Item.Parameters.ExpectedSiteIds | Where-Object { $_ })
    $TableName = 'CippStorageCleanupScan'

    try {
        $SiteResults = [System.Collections.Generic.List[object]]::new()
        foreach ($BatchResult in @($Item.Results)) {
            foreach ($SiteResult in @($BatchResult.Sites)) {
                if ($SiteResult) { $SiteResults.Add($SiteResult) }
            }
        }

        $ActualCount = $SiteResults.Count
        # Runs queued before ExpectedSiteIds existed cannot tell a lost batch from a deleted site.
        if ($ExpectedSiteIds.Count -eq 0 -and $ActualCount -ne $ExpectedSiteCount) {
            throw "StorageCleanupScan completeness check failed for $TenantFilter : expected $ExpectedSiteCount site results, got $ActualCount"
        }

        $ReturnedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Restore = [System.Collections.Generic.List[object]]::new()
        $CollectedCount = 0
        foreach ($SiteResult in $SiteResults) {
            $null = $ReturnedIds.Add([string]$SiteResult.SiteId)
            if ($SiteResult.CollectionStatus -eq 'Skipped') { $Restore.Add($SiteResult.SiteRow) } else { $CollectedCount++ }
        }
        if ($CollectedCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "StorageCleanupScan: no sites collected this run for $TenantFilter (expected $ExpectedSiteCount, returned $ActualCount); prior cache left untouched" -sev Error
            return
        }
        foreach ($Id in $ExpectedSiteIds) {
            if ($ReturnedIds.Contains([string]$Id)) { continue }
            $Restore.Add([PSCustomObject]@{ rowType = 'Site'; id = "${Id}_site"; siteId = [string]$Id; collectionStatus = 'Skipped'; collectionError = 'Site was not returned by its collection batch this run.' })
        }

        $PriorSiteRows = @{}
        $PriorLibraryRows = @{}
        if ($Restore.Count -gt 0) {
            $RestoreIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Restore.siteId), [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Existing in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -TableName $TableName)) {
                $Key = [string]$Existing.siteId
                if (-not $RestoreIds.Contains($Key)) { continue }
                if ($Existing.rowType -eq 'Site') {
                    $PriorSiteRows[$Key] = $Existing
                } elseif ($Existing.rowType -eq 'Library') {
                    if (-not $PriorLibraryRows.ContainsKey($Key)) { $PriorLibraryRows[$Key] = [System.Collections.Generic.List[object]]::new() }
                    $PriorLibraryRows[$Key].Add($Existing)
                }
            }
        }

        $AllRows = [System.Collections.Generic.List[object]]::new()
        foreach ($SiteResult in $SiteResults) {
            if ($SiteResult.CollectionStatus -eq 'Skipped') { continue }
            $AllRows.Add($SiteResult.SiteRow)
            foreach ($Row in @($SiteResult.Rows)) { if ($Row) { $AllRows.Add($Row) } }
        }
        $Restored = 0
        foreach ($SkippedRow in $Restore) {
            $Key = [string]$SkippedRow.siteId
            $SiteRow = $PriorSiteRows[$Key]
            if ($SiteRow) {
                # The prior row keeps its recycle totals; only the status and error are this run's.
                foreach ($Name in 'collectionStatus', 'collectionError') {
                    $SiteRow.PSObject.Properties.Remove($Name)
                    $SiteRow.PSObject.Properties.Add([psnoteproperty]::new($Name, $SkippedRow.$Name))
                }
            } else {
                $SiteRow = $SkippedRow
            }
            $AllRows.Add($SiteRow)
            if ($PriorLibraryRows.ContainsKey($Key)) {
                $Restored++
                $AllRows.AddRange($PriorLibraryRows[$Key])
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -TableName $TableName -Data @($AllRows) -AddCount

        $Sev = if ($Restore.Count -gt 0) { 'Warning' } else { 'Info' }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached StorageCleanupScan for $TenantFilter : $CollectedCount of $ExpectedSiteCount sites collected, $($Restore.Count) skipped or missing ($Restored restored from the prior scan)" -sev $Sev
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store StorageCleanupScan: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
