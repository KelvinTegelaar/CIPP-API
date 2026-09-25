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
        # Check rerun protection - 23 hours, so the daily timer is never blocked by firing a few
        # seconds short of a full 24 hours after the previous run
        $RerunParams = @{
            TenantFilter = 'AllTenants'
            Type         = 'LogCleanup'
            API          = 'LogRetentionCleanup'
            Interval     = 82800
        }
        $Rerun = Test-CIPPRerun @RerunParams
        if ($Rerun) {
            Write-Host 'Log cleanup was recently executed. Skipping to prevent duplicate execution (runs once every 24 hours)'
            return $true
        }

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

        # CippLogs is partitioned by day (yyyyMMdd), so the cutoff is a PartitionKey range the
        # table service can seek to, instead of a Timestamp filter that scans every row
        $CutoffPartition = (Get-Date).ToUniversalTime().AddDays(-$RetentionDays).ToString('yyyyMMdd')

        $TotalDeletedCount = 0
        $BatchSize = 5000

        # Clean up CIPP Logs
        if ($PSCmdlet.ShouldProcess('CippLogs', 'Cleaning up old logs')) {
            $CippLogsTable = Get-CippTable -tablename 'CippLogs'
            $CutoffFilter = "PartitionKey lt '$CutoffPartition'"

            # Process deletions in batches of 10k to avoid timeout
            $HasMoreRecords = $true
            $BatchNumber = 0

            while ($HasMoreRecords) {
                $BatchNumber++
                Write-Host "Processing batch $BatchNumber..."

                # Fetch up to 10k old log entries
                $OldLogs = Get-AzDataTableEntity @CippLogsTable -Filter $CutoffFilter -Property @('PartitionKey', 'RowKey') -First $BatchSize

                if ($OldLogs -and ($OldLogs | Measure-Object).Count -gt 0) {
                    $BatchCount = ($OldLogs | Measure-Object).Count
                    Remove-CIPPAzDataTableEntity @CippLogsTable -Entity $OldLogs -Force
                    $TotalDeletedCount += $BatchCount
                    Write-Host "Batch $BatchNumber`: Deleted $BatchCount log entries"

                    # If we got less than the batch size, we're done
                    if ($BatchCount -lt $BatchSize) {
                        $HasMoreRecords = $false
                    }
                } else {
                    Write-Host 'No more old logs found'
                    $HasMoreRecords = $false
                }
            }

            if ($TotalDeletedCount -gt 0) {
                Write-LogMessage -API 'LogRetentionCleanup' -message "Deleted $TotalDeletedCount old log entries in $BatchNumber batch(es) (retention: $RetentionDays days)" -Sev 'Info'
                Write-Host "Total deleted: $TotalDeletedCount old log entries"
            } else {
                Write-Host 'No old logs found'
            }
        }

        Write-LogMessage -API 'LogRetentionCleanup' -message "Log cleanup completed. Total logs deleted: $TotalDeletedCount (retention: $RetentionDays days)" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'LogRetentionCleanup' -message "Failed to run log cleanup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw
    }
}
