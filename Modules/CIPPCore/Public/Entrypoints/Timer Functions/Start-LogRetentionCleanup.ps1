function Start-LogRetentionCleanup {
    <#
    .SYNOPSIS
    Start the Log Retention Cleanup Timer
    .DESCRIPTION
    This function cleans up old CIPP logs based on the retention policy
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        # Get retention settings
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'LogRetention' and RowKey eq 'Settings'"
        $RetentionSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

        # Default to 90 days if not set
        $RetentionDays = if ($RetentionSettings.RetentionDays) {
            [int]$RetentionSettings.RetentionDays
        } else {
            90
        }

        # Ensure minimum retention of 7 days
        if ($RetentionDays -lt 7) {
            $RetentionDays = 7
        }

        # Ensure maximum retention of 365 days
        if ($RetentionDays -gt 365) {
            $RetentionDays = 365
        }

        Write-Host "Starting log cleanup with retention of $RetentionDays days"

        # Calculate cutoff date
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $DeletedCount = 0

        # Clean up CIPP Logs
        if ($PSCmdlet.ShouldProcess('CippLogs', 'Cleaning up old logs')) {
            $CippLogsTable = Get-CippTable -tablename 'CippLogs'
            $CutoffFilter = "Timestamp lt datetime'$CutoffDate'"

            # Fetch all old log entries
            $OldLogs = Get-AzDataTableEntity @CippLogsTable -Filter $CutoffFilter -Property @('PartitionKey', 'RowKey', 'ETag')
            if ($OldLogs) {
                # Delete logs in batches to avoid overwhelming the table service
                $BatchSize = 100
                $LogBatches = @()
                $CurrentBatch = @()

                foreach ($Log in $OldLogs) {
                    $CurrentBatch += $Log
                    if ($CurrentBatch.Count -ge $BatchSize) {
                        $LogBatches += , @($CurrentBatch)
                        $CurrentBatch = @()
                    }
                }

                # Add remaining logs as final batch
                if ($CurrentBatch.Count -gt 0) {
                    $LogBatches += , @($CurrentBatch)
                }

                # Delete logs in batches
                foreach ($Batch in $LogBatches) {
                    try {
                        Remove-AzDataTableEntity @CippLogsTable -Entity $Batch -Force
                        $DeletedCount += $Batch.Count
                        Write-Host "Deleted batch of $($Batch.Count) log entries"
                    } catch {
                        Write-LogMessage -API 'LogRetentionCleanup' -message "Failed to delete log batch: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }

                if ($DeletedCount -gt 0) {
                    Write-LogMessage -API 'LogRetentionCleanup' -message "Deleted $DeletedCount old log entries (retention: $RetentionDays days)" -Sev 'Info'
                    Write-Host "Deleted $DeletedCount old log entries"
                } else {
                    Write-Host 'No old logs found'
                }
            } else {
                Write-Host 'No old logs found'
            }
        }

        Write-LogMessage -API 'LogRetentionCleanup' -message "Log cleanup completed. Total logs deleted: $DeletedCount (retention: $RetentionDays days)" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'LogRetentionCleanup' -message "Failed to run log cleanup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw
    }
}
