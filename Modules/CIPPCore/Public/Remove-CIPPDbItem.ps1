function Remove-CIPPDbItem {
    <#
    .SYNOPSIS
        Remove an item from the CIPP Reporting database

    .DESCRIPTION
        Removes a specific item from the CippReportingDB table using partition key (tenant)
        and either Type+ItemId or an explicit RowKey. Decrements the matching {Type}-Count
        row when a data row (not the Count row itself) is removed.

    .PARAMETER TenantFilter
        The tenant domain or GUID (partition key)

    .PARAMETER Type
        The type of data being removed (used to find and update count)

    .PARAMETER ItemId
        The item ID or identifier to remove (used in row key)

    .PARAMETER RowKey
        Explicit table RowKey (preferred when the caller already has storage keys)

    .PARAMETER ETag
        Optional ETag when deleting by RowKey

    .EXAMPLE
        Remove-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'MailboxRules' -ItemId 'rule-id-123'

    .EXAMPLE
        Remove-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users' -RowKey 'Users-abc-123'
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByItemId')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByItemId')]
        [string]$ItemId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByRowKey')]
        [string]$RowKey,

        [Parameter(ParameterSetName = 'ByRowKey')]
        [string]$ETag
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            $TenantLookup = Get-Tenants -TenantFilter $TenantFilter
            if ($TenantLookup) {
                $TenantFilter = $TenantLookup.defaultDomainName
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByItemId') {
            # Sanitize the ItemId for RowKey (same as in Add-CIPPDbItem)
            $SanitizedId = $ItemId -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''
            $RowKey = "$Type-$SanitizedId"
        } else {
            $ExpectedPrefix = "$Type-"
            if (-not $RowKey.StartsWith($ExpectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "RowKey '$RowKey' does not match type '$Type'"
            }
        }

        $Filter = "PartitionKey eq '$TenantFilter' and RowKey eq '$RowKey'"
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if ($Entity) {
            if ($ETag) {
                $Entity | Add-Member -MemberType NoteProperty -Name 'ETag' -Value $ETag -Force
            }
            Remove-CIPPAzDataTableEntity @Table -Entity $Entity -Force
            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Removed $Type row: $RowKey" -sev Debug

            # Do not decrement when removing the Count row itself
            if ($RowKey -eq "$Type-Count") {
                return
            }

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
            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Item not found for removal: $Type row $RowKey" -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to remove $Type item: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
