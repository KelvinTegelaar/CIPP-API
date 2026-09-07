function Set-CIPPDBCacheOneDriveLongPaths {
    <#
    .SYNOPSIS
        Fans out OneDrive long-path recount, one resumable activity per personal site.

    .DESCRIPTION
        Adhoc-only (not part of nightly SharePoint collection). Enumerates personal sites, resolves
        owner UPN from OneDriveUsage cache (merging a live usage report for gaps), and starts
        per-site activities that full-recount path-length counts without storing paths or names.

        Clears the previous OneDriveLongPaths cache at fan-out start so departed users cannot
        leave stale alert counts. Mid-scan the cache may be partial until activities finish.

        Trigger: /api/ExecCIPPDBCache?Name=OneDriveLongPaths&TenantFilter=...
        Alert Get-CIPPAlertOneDriveLongPaths reads the resulting cache — run this collection first.

    .PARAMETER TenantFilter
        The tenant to scan

    .PARAMETER QueueId
        Optional queue ID for progress tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting OneDrive long-path collection (per-site fan-out)' -sev Debug

        $OrgDisplayName = 'Organization'
        try {
            $Org = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName' -tenantid $TenantFilter -asapp $true
            $OrgRow = @($Org)[0]
            if ($OrgRow.displayName) { $OrgDisplayName = [string]$OrgRow.displayName }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: could not read organization displayName; using default: $($_.Exception.Message)" -sev Warning
        }
        # Default sync root: C:\Users\{upnLocal}\OneDrive - {org}\ — org segment once per tenant; UPN local-part added per site.
        $InferredLocalRootFixedLength = ('C:\Users\').Length + ("\OneDrive - $OrgDisplayName\").Length

        $RawSites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$filter=isPersonalSite eq true&`$select=id,webUrl,displayName,sharepointIds&`$top=999" -tenantid $TenantFilter -asapp $true)
        $SeenSiteIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Sites = foreach ($Site in $RawSites) {
            $GraphSiteId = [string]$Site.id
            if ([string]::IsNullOrWhiteSpace($GraphSiteId)) { continue }
            if (-not $SeenSiteIds.Add($GraphSiteId)) { continue }
            $Site
        }
        $Sites = @($Sites)

        # siteId -> ownerPrincipalName (usage report siteId is the SPO GUID)
        $UpnBySiteId = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        try {
            $UsageItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveUsage' | Where-Object { $_.RowKey -ne 'OneDriveUsage-Count' })
            foreach ($UsageItem in $UsageItems) {
                $UsageRow = $null
                try { $UsageRow = $UsageItem.Data | ConvertFrom-Json -Depth 5 } catch { continue }
                if ($UsageRow.siteId -and $UsageRow.ownerPrincipalName) {
                    $UpnBySiteId[[string]$UsageRow.siteId] = [string]$UsageRow.ownerPrincipalName
                }
            }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: OneDriveUsage cache read failed: $($_.Exception.Message)" -sev Debug
        }

        $NeedsLiveUsage = ($UpnBySiteId.Count -eq 0)
        if (-not $NeedsLiveUsage) {
            foreach ($Site in $Sites) {
                $SpoSiteId = [string]($Site.sharepointIds.siteId ?? '')
                if ($SpoSiteId -and -not $UpnBySiteId.ContainsKey($SpoSiteId)) {
                    $NeedsLiveUsage = $true
                    break
                }
            }
        }

        if ($NeedsLiveUsage) {
            try {
                $Usage = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application/json&`$top=999" -tenantid $TenantFilter -asapp $true)
                foreach ($UsageRow in $Usage) {
                    if ($UsageRow.siteId -and $UsageRow.ownerPrincipalName) {
                        $UpnBySiteId[[string]$UsageRow.siteId] = [string]$UsageRow.ownerPrincipalName
                    }
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: live usage report failed: $($_.Exception.Message)" -sev Warning
            }
        }

        if ($Sites.Count -eq 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveLongPaths' -Data @() -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'OneDrive long-paths: no personal sites; wrote empty cache' -sev Debug
            return
        }

        $ScanId = [guid]::NewGuid().ToString()
        $StateTable = Get-CippTable -tablename 'CippOneDriveLongPathsState'
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = 'scan'
            ScanId       = $ScanId
            StartedUtc   = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        } -Force

        # Drop prior scan results so departed users cannot leave false alert counts.
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveLongPaths' -Data @() -ClearOnEmpty

        $Batch = [System.Collections.Generic.List[object]]::new()
        foreach ($Site in $Sites) {
            $SpoSiteId = [string]($Site.sharepointIds.siteId ?? '')
            $GraphSiteId = [string]$Site.id
            $Upn = $null
            if ($SpoSiteId -and $UpnBySiteId.ContainsKey($SpoSiteId)) {
                $Upn = $UpnBySiteId[$SpoSiteId]
            } elseif ($GraphSiteId -and $UpnBySiteId.ContainsKey($GraphSiteId)) {
                $Upn = $UpnBySiteId[$GraphSiteId]
            }

            $QueueLabel = if ($Upn) { $Upn } else { $GraphSiteId }
            $Batch.Add([PSCustomObject]@{
                    FunctionName                 = 'DBCacheOneDriveLongPaths'
                    TenantFilter                 = $TenantFilter
                    SiteId                       = $GraphSiteId
                    SpoSiteId                    = $SpoSiteId
                    OwnerPrincipalName           = $Upn
                    OrgDisplayName               = $OrgDisplayName
                    InferredLocalRootFixedLength = $InferredLocalRootFixedLength
                    ScanId                       = $ScanId
                    QueueId                      = $QueueId
                    QueueName                    = "OneDrive Long Paths - $QueueLabel"
                })
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: dispatching $($Batch.Count) sites, scan $ScanId" -sev Debug

        if ($QueueId) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Batch.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: could not update queue ${QueueId}: $($_.Exception.Message)" -sev Warning
            }
        }

        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = "OneDriveLongPaths_$TenantFilter"
                SkipLog          = $true
            })
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start OneDrive long-path collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
