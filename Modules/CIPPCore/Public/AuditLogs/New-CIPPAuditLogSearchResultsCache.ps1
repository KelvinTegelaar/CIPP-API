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
            Write-LogMessage -API 'AuditLog' -tenant $TenantFilter -message $message -Sev 'Info'
            Write-Information $message
            exit 0
        }
    } catch {
        Write-Information "Error checking for failed downloads: $($_.Exception.Message)"
        # Continue with the process even if the rerun protection check fails
    }

    try {
        Write-Information "Starting audit log cache process for tenant: $TenantFilter"
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $CacheWebhookStatsTable = Get-CippTable -TableName 'CacheWebhookStats'

        # Check if we haven't already downloaded this search by checking the cache table
        $searchEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'"
        if ($searchEntity) {
            Write-Information "Search ID: $SearchId already cached for tenant: $TenantFilter"
            exit 0
        }

        # Record this attempt in the FailedAuditLogDownloads table BEFORE starting the download
        # This way, if the function is killed before completion, the record will remain
        try {
            $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
            $attemptId = [guid]::NewGuid().ToString()
            $failedEntity = @{
                RowKey       = $attemptId
                PartitionKey = $TenantFilter
                SearchId     = $SearchId
                ErrorMessage = 'Download attempt in progress'
            }
            Add-CIPPAzDataTableEntity @FailedDownloadsTable -Entity $failedEntity -Force
            Write-Information "Recorded download attempt for search ID: $SearchId, tenant: $TenantFilter"
        } catch {
            Write-Information "Failed to record download attempt: $($_.Exception.Message)"
            # Continue with the process even if recording the attempt fails
        }

        # Start tracking download time
        $downloadStartTime = Get-Date

        # Process each search and store results in cache
        try {
            Write-Information "Processing search ID: $($SearchId) for tenant: $TenantFilter"
            # Get the search results
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
            Write-Information "Successfully cached search ID: $($SearchId) for tenant: $TenantFilter"

            # If we get here, the download was successful, so remove the failed download record
            try {
                $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
                # Get all records for this tenant and search ID
                $failedEntities = Get-CIPPAzDataTableEntity @FailedDownloadsTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'"

                # Remove each record
                foreach ($entity in $failedEntities) {
                    Remove-CIPPAzDataTableEntity @FailedDownloadsTable -Entity $entity
                }

                if ($failedEntities) {
                    Write-Information "Removed failed download records for search ID: $SearchId, tenant: $TenantFilter"
                }
            } catch {
                Write-Information "Failed to remove download attempt record: $($_.Exception.Message)"
            }
        } catch {
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
            SearchCount  = [string]($searchResults ? $searchResults.Count : 0)
        }

        Add-CIPPAzDataTableEntity @CacheWebhookStatsTable -Entity $statsEntity -Force

        Write-Information "Completed audit log cache process for tenant: $TenantFilter. Download time: $downloadSeconds seconds"

        return ($searchResults ? $searchResults.Count : 0)
    } catch {
        Write-Information "Error in New-CIPPAuditLogSearchResultsCache for tenant: $TenantFilter. Error: $($_.Exception.Message)"
        throw $_
    }
}
