function Get-CIPPSharingLinksRowKeysByPrefix {
    <#
    .SYNOPSIS
        Returns the CippSharingLinks rows under a RowKey prefix, with only their keys, ScanId and itemId.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [AllowEmptyString()][string]$Prefix = ''
    )
    $Table = Get-CippTable -tablename 'CippSharingLinks'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SafePrefix = ConvertTo-CIPPODataFilterValue -Value $Prefix -Type String
    $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~'" -f $SafeTenant, $SafePrefix
    @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey', 'ETag', 'ScanId', 'itemId'))
}
