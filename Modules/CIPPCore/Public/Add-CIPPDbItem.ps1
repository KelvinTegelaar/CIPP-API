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

            # Calculate batch size based on available memory
            $AvailableMemory = [System.GC]::GetTotalMemory($false)
            $AvailableMemoryMB = [math]::Round($AvailableMemory / 1MB, 2)

            # Estimate item size from first item (with fallback)
            $EstimatedItemSizeBytes = 1KB # Default assumption
            if ($Data.Count -gt 0) {
                $SampleJson = $Data[0] | ConvertTo-Json -Depth 10 -Compress
                $EstimatedItemSizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($SampleJson)
            }

            # Use 25% of available memory for batch processing, with min/max bounds
            $TargetBatchMemoryMB = [Math]::Max(50, $AvailableMemoryMB * 0.25)
            $CalculatedBatchSize = [Math]::Floor(($TargetBatchMemoryMB * 1MB) / $EstimatedItemSizeBytes)
            # Reduce max to 500 to prevent OOM with large datasets
            $BatchSize = [Math]::Max(100, [Math]::Min(500, $CalculatedBatchSize))

            $TotalCount = $Data.Count
            $ProcessedCount = 0
            Write-Information "Adding $TotalCount items of type $Type to CIPP Reporting DB for tenant $TenantFilter | Available Memory: ${AvailableMemoryMB}MB | Target Memory: ${TargetBatchMemoryMB}MB | Calculated: $CalculatedBatchSize | Batch Size: $BatchSize (est. item size: $([math]::Round($EstimatedItemSizeBytes/1KB, 2))KB)"
            for ($i = 0; $i -lt $TotalCount; $i += $BatchSize) {
                $BatchEnd = [Math]::Min($i + $BatchSize, $TotalCount)
                $Batch = $Data[$i..($BatchEnd - 1)]

                $Entities = foreach ($Item in $Batch) {
                    $ItemId = $Item.id ?? $Item.ExternalDirectoryObjectId ?? $Item.Identity ?? $Item.skuId
                    @{
                        PartitionKey = $TenantFilter
                        RowKey       = Format-RowKey "$Type-$ItemId"
                        Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                        Type         = $Type
                    }
                }

                Add-CIPPAzDataTableEntity @Table -Entity $Entities -Force | Out-Null
                $ProcessedCount += $Batch.Count

                # Clear batch variables to free memory
                $Entities = $null
                $Batch = $null
                [System.GC]::Collect()
            }

        }
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $($Data.Count) items of type $Type$(if ($Count) { ' (count mode)' })" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to add items of type $Type : $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
