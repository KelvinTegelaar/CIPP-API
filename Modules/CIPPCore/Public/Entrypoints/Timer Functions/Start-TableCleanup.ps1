function Start-TableCleanup {
    <#
    .SYNOPSIS
    Start the Table Cleanup Timer
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $CleanupRules = @(
        @{
            DataTableProps = @{
                Context  = (Get-CIPPTable -tablename 'webhookTable').Context
                Property = @('PartitionKey', 'RowKey', 'ETag', 'Resource')
            }
            Where          = "`$_.Resource -match '^Audit'"
        }
        @{
            DataTableProps = @{
                Context  = (Get-CIPPTable -tablename 'AuditLogSearches').Context
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            DataTableProps = @{
                Context  = (Get-CIPPTable -tablename 'CippFunctionStats').Context
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            DataTableProps = @{
                Context  = (Get-CIPPTable -tablename 'CippQueue').Context
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
        @{
            DataTableProps = @{
                Context  = (Get-CIPPTable -tablename 'CippQueueTasks').Context
                Filter   = "Timestamp lt datetime'$((Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
                First    = 10000
                Property = @('PartitionKey', 'RowKey', 'ETag')
            }
        }
    )

    $DeleteTables = @(
        'knownlocationdb'
    )

    if ($PSCmdlet.ShouldProcess('Start-TableCleanup', 'Starting Table Cleanup')) {
        foreach ($Table in $DeleteTables) {
            try {
                $Table = Get-CIPPTable -tablename $Table
                if ($Table) {
                    Write-Information "Deleting table $($Table.Context.TableName)"
                    try {
                        Remove-AzDataTable -Context $Table.Context -Force
                    } catch {
                        Write-LogMessage -API 'TableCleanup' -message "Failed to delete table $($Table.Context.TableName)" -sev Error -LogData (Get-CippException -Exception $_)
                    }
                }
            } catch {
                Write-Information "Table $Table not found"
            }
        }

        Write-Information 'Starting table cleanup'
        foreach ($Rule in $CleanupRules) {
            if ($Rule.Where) {
                $Where = [scriptblock]::Create($Rule.Where)
            } else {
                $Where = { $true }
            }
            $DataTableProps = $Rule.DataTableProps

            $CleanupCompleted = $false
            do {
                $Entities = Get-AzDataTableEntity @DataTableProps | Where-Object $Where
                if ($Entities) {
                    Write-Information "Removing $($Entities.Count) entities from $($Rule.DataTableProps.Context.TableName)"
                    try {
                        Remove-AzDataTableEntity -Context $DataTableProps.Context -Entity $Entities -Force
                        if ($DataTableProps.First -and $Entities.Count -lt $DataTableProps.First) {
                            $CleanupCompleted = $true
                        }
                    } catch {
                        Write-LogMessage -API 'TableCleanup' -message "Failed to remove entities from $($DataTableProps.Context.TableName)" -sev Error -LogData (Get-CippException -Exception $_)
                        $CleanupCompleted = $true
                    }
                } else {
                    $CleanupCompleted = $true
                }
            } while (!$CleanupCompleted)
        }
        Write-Information 'Table cleanup complete'
    }
}
