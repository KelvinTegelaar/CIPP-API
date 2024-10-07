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
    $Queries = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/auditLog/queries' -AsApp $true -tenantid $TenantFilter
    if ($ReadyToProcess.IsPresent) {
        $AuditLogSearchesTable = Get-CippTable -TableName 'AuditLogSearches'
        $PendingQueries = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "Tenant eq '$TenantFilter' and CippStatus eq 'Pending'"
        $Queries = $Queries | Where-Object { $PendingQueries.RowKey -contains $_.id -and $_.status -eq 'succeeded' }
    }
    return $Queries
}
