function Remove-CIPPDbItem {
    <#
    .SYNOPSIS
        Remove an item from the CIPP Reporting database

    .DESCRIPTION
        Removes a specific item from the CippReportingDB table using partition key (tenant) and row key (item ID)

    .PARAMETER TenantFilter
        The tenant domain or GUID (partition key)

    .PARAMETER Type
        The type of data being removed (used to find and update count)

    .PARAMETER ItemId
        The item ID or identifier to remove (used in row key)

    .EXAMPLE
        Remove-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'MailboxRules' -ItemId 'rule-id-123'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$ItemId
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        # Sanitize the ItemId for RowKey (same as in Add-CIPPDbItem)
        $SanitizedId = $ItemId -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''
        $RowKey = "$Type-$SanitizedId"

        # Try to get the entity
        $Filter = "PartitionKey eq '$TenantFilter' and RowKey eq '$RowKey'"
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if ($Entity) {
            # Remove the entity
            Remove-AzDataTableEntity @Table -Entity $Entity -Force
            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Removed $Type item with ID: $ItemId" -sev Debug

            # Always decrement count
            try {
                $CountRowKey = "$Type-Count"
                $CountFilter = "PartitionKey eq '$TenantFilter' and RowKey eq '$CountRowKey'"
                $CountEntity = Get-CIPPAzDataTableEntity @Table -Filter $CountFilter

                if ($CountEntity -and $CountEntity.DataCount -gt 0) {
                    $CountEntity.DataCount = [int]$CountEntity.DataCount - 1
                    Add-CIPPAzDataTableEntity @Table -Entity @{
                        PartitionKey = $CountEntity.PartitionKey
                        RowKey       = $CountEntity.RowKey
                        DataCount    = $CountEntity.DataCount
                        ETag         = $CountEntity.ETag
                    } -Force | Out-Null
                    Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Decremented $Type count to $($CountEntity.DataCount)" -sev Debug
                }
            } catch {
                Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to decrement count for $Type : $($_.Exception.Message)" -sev Warning
            }
        } else {
            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Item not found for removal: $Type with ID $ItemId" -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to remove $Type item: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
