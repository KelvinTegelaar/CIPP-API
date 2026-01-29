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
    try {
        $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
        $fourHoursAgo = (Get-Date).AddHours(-4).ToUniversalTime()
        $failedEntity = Get-CIPPAzDataTableEntity @FailedDownloadsTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId' and Timestamp ge datetime'$($fourHoursAgo.ToString('yyyy-MM-ddTHH:mm:ssZ'))'"

        if ($failedEntity) {
            $message = "Skipping search ID: $SearchId for tenant: $TenantFilter - Previous attempt failed within the last 4 hours"
            Write-LogMessage -API 'AuditLog' -tenant $TenantFilter -message $message -Sev 'Info'
            Write-Information $message
            return $false
        }
    } catch {
        Write-Information "Error checking for failed downloads: $($_.Exception.Message)"
    }

    try {
        Write-Information "Starting audit log cache process for tenant: $TenantFilter"
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $CacheWebhookStatsTable = Get-CippTable -TableName 'CacheWebhookStats'
        # Check if we haven't already downloaded this search by checking the cache table
        $searchEntity = Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'"
        if ($searchEntity) {
            Write-Information "Search ID: $SearchId already cached for tenant: $TenantFilter"
            return $false
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
        }

        $downloadStartTime = Get-Date
        try {
            Write-Information "Processing search ID: $($SearchId) for tenant: $TenantFilter"
            $searchResults = Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId
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
            try {
                $FailedDownloadsTable = Get-CippTable -TableName 'FailedAuditLogDownloads'
                $failedEntities = Get-CIPPAzDataTableEntity @FailedDownloadsTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'"
                if ($failedEntities) {
                    Remove-AzDataTableEntity @FailedDownloadsTable -Entity $failedEntities -Force
                    Write-Information "Removed failed download records for search ID: $SearchId, tenant: $TenantFilter"
                }
            } catch {
                Write-Information "Failed to remove download attempt record: $($_.Exception.Message)"
            }
        } catch {
            throw $_
        }

        $downloadEndTime = Get-Date
        $downloadSeconds = ($downloadEndTime - $downloadStartTime).TotalSeconds

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
