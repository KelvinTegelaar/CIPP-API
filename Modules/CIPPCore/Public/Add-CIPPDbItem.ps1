function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database

    .DESCRIPTION
        Adds items to the CippReportingDB table with support for bulk inserts, count mode, and pipeline streaming

    .PARAMETER TenantFilter
        The tenant domain or GUID (used as partition key)

    .PARAMETER Type
        The type of data being stored (used in row key)

    .PARAMETER InputObject
        Items to add to the database. Accepts pipeline input for memory-efficient streaming.
        Alias: Data (for backward compatibility)

    .PARAMETER Count
        If specified, stores a single row with count of items processed

    .PARAMETER AddCount
        If specified, automatically records the total count after processing all items

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData

    .EXAMPLE
        New-GraphGetRequest -uri '...' | Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users' -AddCount

    .EXAMPLE
        Add-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups' -Data $GroupsData -Count
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('Data')]
        [AllowNull()]
        [AllowEmptyCollection()]
        $InputObject,

        [Parameter(Mandatory = $false)]
        [switch]$Count,

        [Parameter(Mandatory = $false)]
        [switch]$AddCount
    )

    begin {
        # Initialize pipeline processing with state hashtable for nested function access
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $BatchAccumulator = [System.Collections.Generic.List[hashtable]]::new(500)
        $State = @{
            TotalProcessed = 0
            BatchNumber    = 0
        }

        # Helper function to format RowKey values by removing disallowed characters
        function Format-RowKey {
            param([string]$RowKey)
            $sanitized = $RowKey -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''
            return $sanitized
        }

        # Function to flush current batch
        function Invoke-FlushBatch {
            param($State)
            if ($BatchAccumulator.Count -eq 0) { return }

            $State.BatchNumber++
            $batchSize = $BatchAccumulator.Count
            $MemoryBeforeGC = [System.GC]::GetTotalMemory($false)
            $flushStart = Get-Date

            try {
                # Entities are already in the accumulator, just write them
                $writeStart = Get-Date
                Add-CIPPAzDataTableEntity @Table -Entity $BatchAccumulator.ToArray() -Force | Out-Null
                $writeEnd = Get-Date
                $writeDuration = [math]::Round(($writeEnd - $writeStart).TotalSeconds, 2)
                $State.TotalProcessed += $batchSize

            } finally {
                # Clear and GC
                $gcStart = Get-Date
                $BatchAccumulator.Clear()

                # Single GC pass is sufficient - aggressive GC was causing slowdown
                [System.GC]::Collect()

                $flushEnd = Get-Date
                $gcDuration = [math]::Round(($flushEnd - $gcStart).TotalSeconds, 2)
                $flushDuration = [math]::Round(($flushEnd - $flushStart).TotalSeconds, 2)
                $MemoryAfterGC = [System.GC]::GetTotalMemory($false)
                $FreedMB = [math]::Round(($MemoryBeforeGC - $MemoryAfterGC) / 1MB, 2)
                $CurrentMemoryMB = [math]::Round($MemoryAfterGC / 1MB, 2)
                #Write-Debug "Batch $($State.BatchNumber): ${flushDuration}s total (write: ${writeDuration}s, gc: ${gcDuration}s) | Processed: $($State.TotalProcessed) | Memory: ${CurrentMemoryMB}MB | Freed: ${FreedMB}MB"
            }
        }

        if (-not $Count.IsPresent) {
            # Delete existing entries for this type
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}0'" -f $TenantFilter, $Type
            $ExistingEntities = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag
            if ($ExistingEntities) {
                Remove-AzDataTableEntity @Table -Entity $ExistingEntities -Force | Out-Null
            }
            $AllocatedMemoryMB = [math]::Round([System.GC]::GetTotalMemory($false) / 1MB, 2)
            #Write-Debug "Starting $Type import for $TenantFilter | Allocated Memory: ${AllocatedMemoryMB}MB | Batch Size: 500"
        }
    }

    process {
        # Process each item from pipeline
        if ($null -eq $InputObject) { return }

        # If Count mode and InputObject is an integer, use it directly as count
        if ($Count.IsPresent -and $InputObject -is [int]) {
            $State.TotalProcessed = $InputObject
            return
        }

        # Handle both single items and arrays (for backward compatibility)
        $ItemsToProcess = if ($InputObject -is [array]) {
            $InputObject
        } else {
            @($InputObject)
        }

        # If Count mode, just count items without processing
        if ($Count.IsPresent) {
            $itemCount = if ($ItemsToProcess -is [array]) { $ItemsToProcess.Count } else { 1 }
            $State.TotalProcessed += $itemCount
            return
        }

        foreach ($Item in $ItemsToProcess) {
            if ($null -eq $Item) { continue }

            # Convert to entity
            $ItemId = $Item.ExternalDirectoryObjectId ?? $Item.id ?? $Item.Identity ?? $Item.skuId
            $Entity = @{
                PartitionKey = $TenantFilter
                RowKey       = Format-RowKey "$Type-$ItemId"
                Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                Type         = $Type
            }

            $BatchAccumulator.Add($Entity)

            # Flush when batch reaches 500 items
            if ($BatchAccumulator.Count -ge 500) {
                Invoke-FlushBatch -State $State
            }
        }
    }

    end {
        try {
            # Flush any remaining items in final partial batch
            if ($BatchAccumulator.Count -gt 0) {
                Invoke-FlushBatch -State $State
            }

            if ($Count.IsPresent) {
                # Store count record
                $Entity = @{
                    PartitionKey = $TenantFilter
                    RowKey       = Format-RowKey "$Type-Count"
                    DataCount    = [int]$State.TotalProcessed
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
            }

            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter `
                -message "Added $($State.TotalProcessed) items of type $Type$(if ($Count.IsPresent) { ' (count mode)' })" -sev Debug

        } catch {
            Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter `
                -message "Failed to add items of type $Type : $($_.Exception.Message)" -sev Error `
                -LogData (Get-CippException -Exception $_)
            #Write-Debug "[Add-CIPPDbItem] $TenantFilter - $(Get-CippException -Exception $_ | ConvertTo-Json -Depth 5 -Compress)"
            throw
        } finally {
            # Record count if AddCount was specified
            if ($AddCount.IsPresent -and $State.TotalProcessed -gt 0) {
                try {
                    Add-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -InputObject $State.TotalProcessed -Count
                } catch {
                    Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter `
                        -message "Failed to record count for $Type : $($_.Exception.Message)" -sev Warning
                }
            }

            # Final cleanup
            $BatchAccumulator = $null
            [System.GC]::Collect()
        }
    }
}
