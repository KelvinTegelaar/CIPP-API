function Set-CIPPDBCacheSharePointSharingLinks {
    <#
    .SYNOPSIS
        Fans out SharePoint & OneDrive sharing link collection, one resumable activity per site.

    .DESCRIPTION
        Enumerates every site in the tenant (SharePoint sites and OneDrive personal sites) and the
        tenant's verified domains, then starts a child orchestration with one activity per site
        (Push-DBCacheSharePointSiteSharingLinks). Each site activity scans its own drives for shared
        items and writes sharing-link rows straight to the CippSharingLinks table as it goes.

        Site activities are resumable: each checkpoints its delta position after every persisted
        page, so a run killed by a timeout or recycle loses at most one page — re-dispatching the
        same task payload resumes where the dead run stopped, and completion is idempotent, so a
        task-level retry mechanism can safely fire a site's task again at any time (large sites
        previously hit the activity timeout, were retried from scratch and never completed).
        Drives that completed a previous scan store their Graph deltaLink and are scanned
        incrementally — only changed items are processed. A drive is rescanned in full only when
        it has no token, the token is rejected, or it holds fewer rows than it last recorded.

        Completion is tracked in the CippSharingLinksState table; the activity that finishes the
        last site runs Push-StoreSharePointSharingLinks to prune rows for drives that no longer
        exist and record the tenant's link count. There is deliberately no PostExecution aggregation:
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
        # Every row and task is keyed on the default domain; a tenant id is resolved here once.
        if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            $TenantFilter = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)[0].defaultDomainName ?? $TenantFilter
        }
        $Running = Get-CIPPSharingLinksScanStatus -TenantFilter $TenantFilter
        if ($Running.inProgress) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links scan already running (started $($Running.startedUtc)); not starting another" -sev Info
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting SharePoint/OneDrive sharing link collection (per-site fan-out)' -sev Debug

        # Verified domains, used by each site activity to tell internal from external recipients.
        $InternalDomains = [System.Collections.Generic.List[string]]::new()
        try {
            $Domains = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/domains?`$select=id,isVerified" -tenantid $TenantFilter -asapp $true
            foreach ($Domain in ($Domains | Where-Object { $_.isVerified })) { $InternalDomains.Add([string]$Domain.id) }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not list verified domains for sharing link classification: $($_.Exception.Message)" -sev Warning
        }

        # Lets each site task ask SharePoint which of its libraries hold their own permissions.
        $SharePointUrl = try { (Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter).SharePointUrl } catch { $null }

        # All sites, including OneDrive personal sites. Cheap - just the site list, no drive scan here.
        $Sites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true)

        if ($Sites.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No sites found; clearing cached sharing links' -sev Debug
            $null = Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter
            $SummaryTable = Get-CippTable -tablename 'CippSharingLinksState'
            $null = Add-CIPPAzDataTableEntity @SummaryTable -Entity @{
                PartitionKey = $TenantFilter
                RowKey       = 'summary'
                LinkCount    = 0
                CompletedUtc = [string]([DateTimeOffset]::UtcNow.ToString('o'))
            } -Force
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

        # Scan state lives in CippSharingLinksState, partitioned per tenant. Completion is
        # tracked purely with insert-only marker rows (see the site/drive activity for the row
        # vocabulary) - deliberately no pending counter and no failed-site list on this row:
        # concurrent counter decrements lost ETag races, and the failed-site JSON overflowed the
        # 64KB table property cap at ~315 SharePoint composite site ids, both of which left
        # scans permanently uncompletable.
        $StateTable = Get-CippTable -tablename 'CippSharingLinksState'

        # Markers are per scan: clear the previous scan's before any site of this one can
        # finish, or every site would look like a duplicate. Stale rows are ScanId-gated by
        # their readers, but sweep them too so table state always reflects at most one scan.
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        foreach ($Prefix in @('done-', 'ddone-', 'drives-', 'chk-', 'final')) {
            $Stale = @(Get-CIPPAzDataTableEntity @StateTable -Filter ("PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~'" -f $SafeTenant, $Prefix) -Property @('PartitionKey', 'RowKey', 'ETag'))
            if ($Stale.Count -gt 0) { $null = Remove-CIPPAzDataTableEntity @StateTable -Entity $Stale -Force }
        }

        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = 'scan'
            ScanId       = $ScanId
            TotalSites   = [int]$Sites.Count
            FullSweep    = [bool]$FullSweep
            StartedUtc   = [string]([DateTimeOffset]::UtcNow.ToString('o'))
            QueueId      = [string]$QueueId
            Phase        = "Listing the libraries of $($Sites.Count) sites"
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
                ForceFull       = [bool]$ForceFullSync
                QueueId         = $QueueId
                QueueName       = "Sharing Links - $($Site.webUrl)"
                SharePointScope = if ($SharePointUrl) { "$SharePointUrl/.default" }
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

        # A user's refresh would otherwise run the whole scan at P1, ahead of every scheduled task.
        $InputObject = [PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = "SharePointSharingLinks_$TenantFilter"
            AllowCollision   = $false
            Priority         = [Math]::Max(2, (Resolve-CIPPOrchestratorPriority -OpContext (Get-Variable -Name 'CraftOperationContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)))
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'SharingLinksDispatchDrives'
                Parameters   = @{
                    TenantFilter    = $TenantFilter
                    ScanId          = $ScanId
                    InternalDomains = @($InternalDomains)
                    ForceFull       = [bool]$ForceFullSync
                    QueueId         = $QueueId
                }
            }
        }

        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started sharing link collection across $($Sites.Count) sites (scan $ScanId)" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start SharePoint sharing link collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
