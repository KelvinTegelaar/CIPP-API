function Set-CIPPDBCacheSharePointSharingLinks {
    <#
    .SYNOPSIS
        Fans out SharePoint & OneDrive sharing link collection, one resumable activity per site.

    .DESCRIPTION
        Enumerates every site in the tenant (SharePoint sites and OneDrive personal sites) and the
        tenant's verified domains, then starts a child orchestration with one activity per site
        (Push-DBCacheSharePointSiteSharingLinks). Each site activity scans its own drives for shared
        items and writes sharing-link rows straight to the reporting DB as it goes.

        Site activities are resumable: each checkpoints its delta position after every persisted
        page, so a run killed by a timeout or recycle loses at most one page — re-dispatching the
        same task payload resumes where the dead run stopped, and completion is idempotent, so a
        task-level retry mechanism can safely fire a site's task again at any time (large sites
        previously hit the activity timeout, were retried from scratch and never completed).
        Drives that completed a previous scan store their Graph deltaLink and are scanned
        incrementally — only changed items are processed — with a periodic full rescan
        (CIPP_SHARINGLINKS_FULLSCAN_DAYS, default 14) bounding any drift.

        Completion is tracked in the CippSharingLinksState table; the activity that finishes the
        last site runs Push-StoreSharePointSharingLinks to prune rows for drives that no longer
        exist and refresh the cached count. There is deliberately no PostExecution aggregation:
        rows stream to storage per page, so the whole tenant's link set is never held in memory.

    .PARAMETER TenantFilter
        The tenant to cache sharing links for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)

    .PARAMETER ForceFullSync
        Ignore stored delta tokens and rescan every drive in full.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId,
        [switch]$ForceFullSync
    )

    try {
        $TenantFilter = Resolve-CIPPSharingLinksTenantFilter -TenantFilter $TenantFilter
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting SharePoint/OneDrive sharing link collection (per-site fan-out)' -sev Debug

        # Verified domains, used by each site activity to tell internal from external recipients.
        $InternalDomains = [System.Collections.Generic.List[string]]::new()
        try {
            $Domains = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains?`$select=id,isVerified" -tenantid $TenantFilter -asapp $true
            foreach ($Domain in ($Domains | Where-Object { $_.isVerified })) { $InternalDomains.Add([string]$Domain.id) }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not list verified domains for sharing link classification: $($_.Exception.Message)" -sev Warning
        }

        # All sites, including OneDrive personal sites. Cheap - just the site list, no drive scan here.
        $Sites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true)

        if ($Sites.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No sites found; writing empty SharePointSharingLinks cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSharingLinks' -Data @() -AddCount
            return
        }

        # One scan generation for the whole run. Every site task (including retried dispatches)
        # carries this id; it stamps every row written, gates stale tasks from a superseded run,
        # and drives the last-site-out finalisation.
        $ScanId = [guid]::NewGuid().ToString()

        # With no delta state at all this is the first scan of the new design (or a fresh
        # tenant): every drive scans full, so finalisation can safely sweep any row this scan
        # did not write - including legacy rows for drives deleted before delta state existed.
        # A forced full sync gets the same sweep for the same reason.
        $FullSweep = [bool]$ForceFullSync -or (@(Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter).Count -eq 0)

        # Scan state lives in CippSharingLinksState, partitioned per tenant:
        #   RowKey 'scan'            - this row: scan identity, pending/total site counters,
        #                              failed-site list, FullSweep flag. One scan per tenant at
        #                              a time; writing it supersedes any scan still in flight.
        #   RowKey 'chk-{siteId}'    - an in-progress site's resume position (written by the
        #                              site activity after every persisted page).
        #   RowKey 'done-{siteId}'   - a site's completion marker for the current scan; its
        #                              insert-only write is what makes counting a site idempotent
        #                              when a retry mechanism dispatches a task more than once.
        #   RowKey 'delta-{driveId}' - per-drive delta token + scan bookkeeping (written by the
        #                              site activity, read via Get-CIPPSharingLinksDriveState).
        $StateTable = Get-CippTable -tablename 'CippSharingLinksState'

        # Completion markers are per scan: clear the previous scan's before any site of this one
        # can finish, or every site would look like a duplicate and the counter would never move.
        # Stale checkpoints are ScanId-gated by the reader, but sweep them too so table state
        # always reflects at most one scan.
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        foreach ($Prefix in @('done-', 'chk-')) {
            $Stale = @(Get-CIPPAzDataTableEntity @StateTable -Filter ("PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~'" -f $SafeTenant, $Prefix) -Property @('PartitionKey', 'RowKey', 'ETag'))
            if ($Stale.Count -gt 0) { $null = Remove-CIPPAzDataTableEntity @StateTable -Entity $Stale -Force }
        }

        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = 'scan'
            ScanId       = $ScanId
            PendingSites = [int]$Sites.Count
            TotalSites   = [int]$Sites.Count
            FailedSites  = '[]'
            FullSweep    = [bool]$FullSweep
            StartedUtc   = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        } -Force

        $Batch = foreach ($Site in $Sites) {
            [PSCustomObject]@{
                FunctionName    = 'DBCacheSharePointSiteSharingLinks'
                TenantFilter    = $TenantFilter
                SiteId          = $Site.id
                SiteName        = $Site.displayName ?? $Site.name
                SiteUrl         = $Site.webUrl
                IsPersonalSite  = [bool]$Site.isPersonalSite
                InternalDomains = @($InternalDomains)
                ScanId          = $ScanId
                Slice           = 1
                ForceFull       = [bool]$ForceFullSync
                QueueId         = $QueueId
                QueueName       = "Sharing Links - $($Site.webUrl)"
            }
        }

        # Track the per-site activities against the same queue counter.
        if ($QueueId) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Sites.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with sharing-link tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $InputObject = [PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = "SharePointSharingLinks_$TenantFilter"
            SkipLog          = $true
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started sharing link collection across $($Sites.Count) sites (scan $ScanId)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start SharePoint sharing link collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
