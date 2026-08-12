function Get-CIPPSharingLinksRowKeysByPrefix {
    <#
    .SYNOPSIS
        Returns the RowKeys (keys only, no Data) under a RowKey prefix.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Prefix
    )
    $Table = Get-CippTable -tablename 'CippReportingDB'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SafePrefix = ConvertTo-CIPPODataFilterValue -Value $Prefix -Type String
    $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~'" -f $SafeTenant, $SafePrefix
    @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey', 'ETag'))
}
