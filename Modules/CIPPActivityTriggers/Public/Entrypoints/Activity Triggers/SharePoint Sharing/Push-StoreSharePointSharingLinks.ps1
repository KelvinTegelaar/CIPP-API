function Push-StoreSharePointSharingLinks {
    <#
    .SYNOPSIS
        Finalises a sharing-links scan: prunes rows for vanished drives and refreshes the count.

    .DESCRIPTION
        Runs once per scan, invoked inline by whichever Push-DBCacheSharePointSiteSharingLinks
        activity completes the tenant's last pending site. Site activities write their rows to
        the reporting DB as they scan, so there is nothing to aggregate here; what remains is
        cross-site housekeeping no single site can decide alone:

        - Drives whose state row was not touched by this scan belong to deleted drives or sites,
          so their cached rows are removed - unless the drive's site is on the scan's failed
          list, in which case its rows survive one more cycle rather than vanish on a transient
          error.
        - The {Type}-Count row is recomputed from the rows actually present, which also absorbs
          whatever adds and tombstones the incremental scans made along the way.

        Idempotent by design: the completion counter's conditional update makes a duplicate
        invocation rare, and re-running prune + recount produces the same result.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        $Item,
        [string]$TenantFilter,
        [string]$ScanId
    )

    if ($Item) {
        $TenantFilter = $Item.Parameters.TenantFilter ?? $TenantFilter
        $ScanId = $Item.Parameters.ScanId ?? $ScanId
    }
    $TenantFilter = Resolve-CIPPSharingLinksTenantFilter -TenantFilter $TenantFilter
    $CacheType = 'SharePointSharingLinks'

    try {
        # If a newer scan superseded this one between the last site completing and this read,
        # pruning against ITS drive states would delete rows it is actively writing. Leave all
        # housekeeping to the newer scan's own finalisation.
        $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        $Scan = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
        $ScanMatches = $Scan -and [string]$Scan.ScanId -eq $ScanId

        # Failed sites come from the completion markers, never from a list on the scan row: a
        # marker row per site has no aggregate size cap, where the old JSON property overflowed
        # the 64KB column limit at ~315 SharePoint composite site ids. The marker key holds the
        # sanitised site id, which is what the drive-state rows' SiteId sanitises to as well.
        $FailedSites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($ScanMatches) {
            $DoneMarkers = @(Get-CIPPAzDataTableEntity @StateTable -Filter ("PartitionKey eq '{0}' and RowKey ge 'done-' and RowKey lt 'done-~'" -f $SafeTenant) -Property @('PartitionKey', 'RowKey', 'ScanId', 'Failed'))
            foreach ($Marker in $DoneMarkers) {
                if ([string]$Marker.ScanId -ne $ScanId) { continue }
                if ([string]$Marker.Failed -ne 'True') { continue }
                [void]$FailedSites.Add(([string]$Marker.RowKey).Substring('done-'.Length))
            }
        }

        # Prune drives this scan never saw: deleted drives and deleted sites. Failed sites keep
        # their rows - their drives were unreachable, not gone.
        $PrunedDrives = 0
        $PrunedRows = 0
        if ($ScanMatches) {
            foreach ($DriveState in @(Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter)) {
                if (-not $DriveState) { continue }
                if ([string]$DriveState.LastScanId -eq $ScanId) { continue }
                # Marker keys carry the sanitised site id; sanitise this row's SiteId the same
                # way before membership testing.
                $DriveSiteKey = [string]$DriveState.SiteId
                if ($DriveSiteKey -and $FailedSites.Contains((ConvertTo-CIPPSharingLinksKeySegment -Value $DriveSiteKey))) { continue }
                $DriveKeySegment = ConvertTo-CIPPSharingLinksKeySegment -Value "$($DriveState.DriveId)"
                $PrunedRows += Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-${DriveKeySegment}_"
                Remove-CIPPAzDataTableEntity @StateTable -Entity $DriveState -Force
                $PrunedDrives++
            }

            # A full-sweep scan (first scan of this design, or a forced full sync) rewrote every
            # current link row with this scan's id, so anything left without it is stale by
            # definition - including rows for drives deleted before delta state existed, which
            # the per-drive prune above can never find.
            if ([bool]$Scan.FullSweep) {
                $PrunedRows += Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-" -ExceptRunId $ScanId -ExceptRowKeys @("$CacheType-Count")
            }
        }

        # Recount from what is actually stored; incremental scans add and tombstone rows all
        # through the run, so a running total would drift where this cannot.
        $CountRowKey = "$CacheType-Count"
        $LinkCount = 0
        foreach ($Row in (Get-CIPPSharingLinksRowKeysByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-")) {
            if ($Row.RowKey -and $Row.RowKey -ne $CountRowKey) { $LinkCount++ }
        }

        $ReportingTable = Get-CippTable -tablename 'CippReportingDB'
        $null = Add-CIPPAzDataTableEntity @ReportingTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $CountRowKey
            DataCount    = [int]$LinkCount
            Type         = $CacheType
        } -Force

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links sync finalised: $LinkCount links cached, $PrunedDrives stale drives pruned ($PrunedRows rows), $($FailedSites.Count) sites failed" -sev Info
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to finalise SharePoint sharing links sync: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
