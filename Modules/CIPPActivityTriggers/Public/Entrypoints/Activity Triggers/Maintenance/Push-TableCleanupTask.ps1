function Push-TableCleanupTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        $Item
    )

    $Type = $Item.Type
    Write-Information "#### Starting $($Type) task..."
    if ($PSCmdlet.ShouldProcess('Start-TableCleanup', 'Starting Table Cleanup')) {
        if ($Type -eq 'DeleteTable') {
            $DeleteTables = $Item.Tables
            foreach ($Table in $DeleteTables) {
                try {
                    $Table = Get-CIPPTable -tablename $Table
                    if ($Table) {
                        Write-Information "Deleting table $($Table.Context.TableName)"
                        try {
                            Remove-AzDataTable -Context $Table.Context -Force
                        } catch {
                            #Write-LogMessage -API 'TableCleanup' -message "Failed to delete table $($Table.Context.TableName)" -sev Error -LogData (Get-CippException -Exception $_)
                        }
                    }
                } catch {
                    Write-Information "Table $Table not found"
                }
            }
            Write-Information "#### $($Type) task complete for $($Item.TableName)"
        } elseif ($Type -eq 'CleanupRule') {
            if ($Item.Where) {
                $Where = [scriptblock]::Create($Item.Where)
            } else {
                $Where = { $true }
            }

            $DataTableProps = $Item.DataTableProps | ConvertTo-Json | ConvertFrom-Json -AsHashtable
            $Table = Get-CIPPTable -tablename $Item.TableName
            $CleanupCompleted = $false

            $RowsRemoved = 0
            do {
                Write-Information "Fetching entities from $($Item.TableName) with filter: $($DataTableProps.Filter)"
                try {
                    $Entities = Get-AzDataTableEntity @Table @DataTableProps | Where-Object $Where
                    if ($Entities) {
                        Write-Information "Removing $($Entities.Count) entities from $($Item.TableName)"
                        try {
                            Remove-AzDataTableEntity @Table -Entity $Entities -Force
                            $RowsRemoved += $Entities.Count
                            if ($DataTableProps.First -and $Entities.Count -lt $DataTableProps.First) {
                                $CleanupCompleted = $true
                            }
                        } catch {
                            Write-LogMessage -API 'TableCleanup' -message "Failed to remove entities from $($Item.TableName)" -sev Error -LogData (Get-CippException -Exception $_)
                            $CleanupCompleted = $true
                        }
                    } else {
                        Write-Information "No entities found for cleanup in $($Item.TableName)"
                        $CleanupCompleted = $true
                    }
                } catch {
                    Write-Warning "Failed to fetch entities from $($Item.TableName): $($_.Exception.Message)"
                    $CleanupCompleted = $true
                }
            } while (!$CleanupCompleted)
            Write-Information "#### $($Type) task complete for $($Item.TableName). Rows removed: $RowsRemoved"
        } else {
            Write-Warning "Unknown task type: $Type"
        }
    }

}
