function Get-CippLastAuditLogSearch {
    <#
    .SYNOPSIS
        Get the last audit log search
    .DESCRIPTION
        Query the Graph API for the last audit log search.
    .PARAMETER TenantFilter
        The tenant to filter on.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Table = Get-CIPPTable -TableName AuditLogSearches
    $LastHour = (Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $LastSearch = Get-AzDataTableEntity @Table -Filter "Tenant eq '$TenantFilter' and Timestamp ge datetime'$LastHour'" | Sort-Object Timestamp -Descending | Select-Object -First 1
    return $LastSearch
}
