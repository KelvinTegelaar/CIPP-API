function Start-TableCleanup {
    <#
    .SYNOPSIS
    Start the Table Cleanup Timer
    #>
    param()

    $Batch = @(
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'webhookTable'
            DataTableProps = @{
                Property = @('PartitionKey', 'RowKey', 'ETag', 'Resource')
                First    = 1000
            }
            Where          = "`$_.Resource -match '^Audit'"
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'AuditLogSearches'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Search' and Timestamp lt datetime'$((Get-Date).AddHours(-12).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippFunctionStats'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Durable' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippQueue'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'CippQueue' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'CippQueueTasks'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'Task' and Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName   = 'TableCleanupTask'
            Type           = 'CleanupRule'
            TableName      = 'ScheduledTasks'
            DataTableProps = @{
                Filter   = "PartitionKey eq 'ScheduledTask' and Command eq 'Sync-CippExtensionData'"
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            FunctionName = 'TableCleanupTask'
            Type         = 'DeleteTable'
            Tables       = @('knownlocationdb', 'CacheExtensionSync', 'ExtensionSync')
        }
    )

    $InputObject = @{
        Batch            = @($Batch)
        OrchestratorName = 'TableCleanup'
        SkipLog          = $true
    }

    Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
}
