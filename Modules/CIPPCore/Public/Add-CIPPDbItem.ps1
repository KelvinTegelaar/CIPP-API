function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database

    .DESCRIPTION
        Adds items to the CippReportingDB table with support for bulk inserts and count mode

    .PARAMETER TenantFilter
        The tenant domain or GUID (used as partition key)

    .PARAMETER Type
        The type of data being stored (used in row key)

    .PARAMETER Data
        Array of items to add to the database

    .PARAMETER Count
        If specified, stores a single row with count of each object property as separate properties

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData -Count
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Data,

        [Parameter(Mandatory = $false)]
        [switch]$Count
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        # Helper function to format RowKey values by removing disallowed characters
        function Format-RowKey {
            param([string]$RowKey)

            # Remove disallowed characters: / \ # ? and control characters (U+0000 to U+001F and U+007F to U+009F)
            $sanitized = $RowKey -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''

            return $sanitized
        }

        if ($Count) {
            $Entity = @{
                PartitionKey = $TenantFilter
                RowKey       = Format-RowKey "$Type-Count"
                DataCount    = [int]$Data.Count
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

        } else {
            #Get the existing type entries and nuke them. This ensures we don't have stale data.
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}0'" -f $TenantFilter, $Type
            $ExistingEntities = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if ($ExistingEntities) {
                Remove-AzDataTableEntity @Table -Entity $ExistingEntities -Force | Out-Null
            }
            $Entities = foreach ($Item in $Data) {
                $ItemId = $Item.id ?? $Item.ExternalDirectoryObjectId ?? $Item.Identity ?? $Item.skuId
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = Format-RowKey "$Type-$ItemId"
                    Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                    Type         = $Type
                }
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entities -Force | Out-Null

        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $($Data.Count) items of type $Type$(if ($Count) { ' (count mode)' })" -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to add items of type $Type : $($_.Exception.Message)" -sev Error
        throw
    }
}
