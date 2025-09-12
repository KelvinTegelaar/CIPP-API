function Get-CippAuditLogSearches {
    <#
    .SYNOPSIS
        Get the available audit log searches
    .DESCRIPTION
        Query the Graph API for available audit log searches.
    .PARAMETER TenantFilter
        The tenant to filter on.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter()]
        [switch]$ReadyToProcess
    )
    $AuditLogSearchesTable = Get-CippTable -TableName 'AuditLogSearches'
    if ($ReadyToProcess.IsPresent) {
        $15MinutesAgo = (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $1DayAgo = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $PendingQueries = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "PartitionKey eq 'Search' and Tenant eq '$TenantFilter' and (CippStatus eq 'Pending' or (CippStatus eq 'Processing' and Timestamp le datetime'$15MinutesAgo')) and Timestamp ge datetime'$1DayAgo'" | Sort-Object Timestamp
    } else {
        $7DaysAgo = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $PendingQueries = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "Tenant eq '$TenantFilter' and Timestamp ge datetime'$7DaysAgo'"
    }

    $BulkRequests = foreach ($PendingQuery in $PendingQueries) {
        @{
            id     = $PendingQuery.RowKey
            url    = 'security/auditLog/queries/' + $PendingQuery.RowKey
            method = 'GET'
        }
    }
    if ($BulkRequests.Count -eq 0) {
        return @()
    }
    $Queries = New-GraphBulkRequest -Requests @($BulkRequests) -AsApp $true -TenantId $TenantFilter | Select-Object -ExpandProperty body

    if ($ReadyToProcess.IsPresent) {
        $Queries = $Queries | Where-Object { $PendingQueries.RowKey -contains $_.id -and $_.status -eq 'succeeded' }
    }

    return $Queries
}
