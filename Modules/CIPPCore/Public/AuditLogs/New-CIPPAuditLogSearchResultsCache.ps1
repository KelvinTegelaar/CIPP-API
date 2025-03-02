function New-CIPPAuditLogSearchResultsCache {
    <#
    .SYNOPSIS
        Cache audit log search results for more efficient processing
    .DESCRIPTION
        Retrieves audit log searches for a tenant, processes them, and stores the results in a cache table.
        Also tracks performance metrics for download and processing times.
    .PARAMETER TenantFilter
        The tenant to filter on.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$SearchId
    )

    # Rerun protection - Check if we already tried downloading this search ID in the last 4 hours
    try {
        $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
        $fourHoursAgo = (Get-Date).AddHours(-4).ToUniversalTime()

        # Check if this search ID has a failed attempt in the last 4 hours
        $failedEntity = Get-CIPPAzDataTableEntity @FailedDownloadsTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId' and Timestamp ge datetime'$($fourHoursAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))'"

        if ($failedEntity) {
            $message = "Skipping search ID: $SearchId for tenant: $TenantFilter - Previous attempt failed within the last 4 hours"
            Write-LogMessage -API "AuditLog" -tenant $TenantFilter -message $message -Sev "Info"
            Write-Information $message
            exit 0
        }
    }
    catch {
        Write-Information "Error checking for failed downloads: $($_.Exception.Message)"
        # Continue with the process even if the rerun protection check fails
    }

    try {
        Write-Information "Starting audit log cache process for tenant: $TenantFilter"
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $CacheWebhookStatsTable = Get-CippTable -TableName 'CacheWebhookStats'
        # Start tracking download time
        $downloadStartTime = Get-Date
        # Process each search and store results in cache
        try {
            Write-Information "Processing search ID: $($SearchId) for tenant: $TenantFilter"
            # Get the search results
            #check if we haven't already downloaded this search by checking the cache table, if there are items with the same search id and tenant, we skip this search
            $searchEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'"
            if ($searchEntity) {
                Write-Information "Search ID: $SearchId already cached for tenant: $TenantFilter"
                exit 0
            }
            $searchResults = Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId
            # Store the results in the cache table
            foreach ($searchResult in $searchResults) {
                $cacheEntity = @{
                    RowKey       = $searchResult.id
                    PartitionKey = $TenantFilter
                    SearchId     = $SearchId
                    JSON         = [string]($searchResult | ConvertTo-Json -Depth 10)
                }
                Add-CIPPAzDataTableEntity @CacheWebhooksTable -Entity $cacheEntity -Force
            }
            Write-Information "Successfully cached search ID: $($item.id) for tenant: $TenantFilter"
        } catch {
            # Record this failed attempt in the FailedAuditLogDownloads table
            try {
                $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
                $failedEntity = @{
                    RowKey       = [guid]::NewGuid().ToString()
                    PartitionKey = $TenantFilter
                    SearchId     = $SearchId
                    ErrorMessage = [string]$_.Exception.Message
                }
                Add-CIPPAzDataTableEntity @FailedDownloadsTable -Entity $failedEntity -Force
                Write-Information "Recorded failed download for search ID: $SearchId, tenant: $TenantFilter"
            }
            catch {
                Write-Information "Failed to record download failure: $($_.Exception.Message)"
            }
            throw $_
        }

        # Calculate download time
        $downloadEndTime = Get-Date
        $downloadSeconds = ($downloadEndTime - $downloadStartTime).TotalSeconds

        # Store performance metrics
        $statsEntity = @{
            RowKey       = $TenantFilter
            PartitionKey = 'Stats'
            DownloadSecs = [string]$downloadSeconds
            SearchCount  = [string]$logSearches.Count
        }

        Add-CIPPAzDataTableEntity @CacheWebhookStatsTable -Entity $statsEntity -Force

        Write-Information "Completed audit log cache process for tenant: $TenantFilter. Download time: $downloadSeconds seconds"

        return $logSearches.Count
    } catch {
        Write-Information "Error in New-CIPPAuditLogSearchResultsCache for tenant: $TenantFilter. Error: $($_.Exception.Message)"
        throw $_
    }
}
