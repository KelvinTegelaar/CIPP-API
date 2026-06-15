function Get-DeltaQueryUrl {
    <#
    .SYNOPSIS
        Retrieves the URL for Delta Queries
    .DESCRIPTION
        This helper function constructs the URL for Delta Query requests based on the resource and parameters.
    .PARAMETER TenantFilter
        The tenant to filter the query on.
    .PARAMETER PartitionKey
        The partition key for the delta query.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $PartitionKey
    )

    $Table = Get-CIPPTable -TableName 'DeltaQueries'
    $DeltaQueryEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$TenantFilter'"

    if ($DeltaQueryEntity) {
        return $DeltaQueryEntity.DeltaUrl
    } else {
        throw "Delta Query not found for Tenant '$TenantFilter' and PartitionKey '$PartitionKey'."
    }
}