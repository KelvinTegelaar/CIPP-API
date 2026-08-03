function Start-BackupRetentionCleanup {
    <#
    .SYNOPSIS
    Start the Backup Retention Cleanup Timer
    .DESCRIPTION
    This function cleans up old CIPP and Tenant backups based on the retention policy.
    Uses pagination and parallel processing for efficient handling of large datasets.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

    # Helper function to delete blobs in parallel with pagination
    function Remove-BackupBlobsInParallel {
        param(
            [Parameter(Mandatory)]
            $Table,
            [Parameter(Mandatory)]
            [string]$Filter,
            [int]$BatchSize = 500,
            [int]$ThrottleLimit = 10
        )

        $TotalBlobsDeleted = 0
        $TotalEntitiesDeleted = 0
        $HasMore = $true

        while ($HasMore) {
            # Fetch batch of blob backups with pagination
            $BlobBackups = Get-AzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey', 'Backup', 'ETag') -First $BatchSize
            $BatchCount = ($BlobBackups | Measure-Object).Count

            if ($BatchCount -eq 0) {
                $HasMore = $false
                continue
            }

            Write-Host "Processing batch of $BatchCount blob backups..."

            # Delete blobs in parallel
            $DeleteResults = $BlobBackups | ForEach-Object -Parallel {
                $Backup = $_
                $Result = @{
                    Success = $false
                    BlobPath = $null
                    Error = $null
                }

                if ($Backup.Backup) {
                    try {
                        $BlobPath = $Backup.Backup
                        # Extract container/blob path from URL
                        if ($BlobPath -like '*:10000/*') {
                            # Azurite format: http://host:10000/devstoreaccount1/container/blob
                            $parts = $BlobPath -split ':10000/'
                            if ($parts.Count -gt 1) {
                                $BlobPath = ($parts[1] -split '/', 2)[-1]
                            }
                        } elseif ($BlobPath -like '*blob.core.windows.net/*') {
                            # Azure Storage format: https://account.blob.core.windows.net/container/blob
                            $BlobPath = ($BlobPath -split '.blob.core.windows.net/', 2)[-1]
                        }

                        $Result.BlobPath = $BlobPath
                        $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $BlobPath -Method 'DELETE'
                        $Result.Success = $true
                    } catch {
                        $Result.Error = $_.Exception.Message
                    }
                }

                $Result
            } -ThrottleLimit $ThrottleLimit

            # Count successful blob deletions
            $SuccessfulDeletes = ($DeleteResults | Where-Object { $_.Success }).Count
            $TotalBlobsDeleted += $SuccessfulDeletes

            # Log any errors
            $FailedDeletes = $DeleteResults | Where-Object { $_.Error }
            foreach ($Failed in $FailedDeletes) {
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete blob $($Failed.BlobPath): $($Failed.Error)" -Sev 'Warning'
            }

            # Delete table entities for this batch (even if blob delete failed - blob may already be gone)
            try {
                Remove-CIPPAzDataTableEntity @Table -Entity $BlobBackups -Force -ErrorAction Stop
                $TotalEntitiesDeleted += $BatchCount
            } catch {
                if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound') {
                    Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete table entities: $($_.Exception.Message)" -Sev 'Warning'
                }
            }

            # Check if we got a full batch (more data might exist)
            if ($BatchCount -lt $BatchSize) {
                $HasMore = $false
            }

            Write-Host "Batch complete: $SuccessfulDeletes blobs deleted"
        }

        @{
            BlobsDeleted = $TotalBlobsDeleted
            EntitiesDeleted = $TotalEntitiesDeleted
        }
    }

    # Helper function to delete table-only backups with pagination
    function Remove-TableBackupsInBatches {
        param(
            [Parameter(Mandatory)]
            $Table,
            [Parameter(Mandatory)]
            [string]$Filter,
            [int]$BatchSize = 1000
        )

        $TotalDeleted = 0
        $HasMore = $true

        while ($HasMore) {
            # Fetch batch with pagination
            $AllBackups = Get-AzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey', 'ETag', 'BackupIsBlob') -First $BatchSize
            # Filter out blob entries client-side (null check is unreliable in filters)
            $TableBackups = $AllBackups | Where-Object { $_.BackupIsBlob -ne $true }
            $BatchCount = ($TableBackups | Measure-Object).Count

            if ($BatchCount -eq 0) {
                # Check if we got blob entries but no table entries
                if (($AllBackups | Measure-Object).Count -lt $BatchSize) {
                    $HasMore = $false
                }
                continue
            }

            try {
                Remove-CIPPAzDataTableEntity @Table -Entity $TableBackups -Force -ErrorAction Stop
                $TotalDeleted += $BatchCount
                Write-Host "Deleted batch of $BatchCount table-only backups"
            } catch {
                if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound') {
                    Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete table backups: $($_.Exception.Message)" -Sev 'Warning'
                }
            }

            # Check if we got a full batch (more data might exist)
            if (($AllBackups | Measure-Object).Count -lt $BatchSize) {
                $HasMore = $false
            }
        }

        $TotalDeleted
    }

    try {
        # Get retention settings
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'BackupRetention' and RowKey eq 'Settings'"
        $RetentionSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

        # Default to 30 days if not set
        $RetentionDays = if ($RetentionSettings.RetentionDays) {
            [int]$RetentionSettings.RetentionDays
        } else {
            30
        }

        # Ensure minimum retention of 7 days
        if ($RetentionDays -lt 7) {
            $RetentionDays = 7
        }

        Write-Host "Starting backup cleanup with retention of $RetentionDays days"

        # Calculate cutoff date
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $DeletedCounts = [System.Collections.Generic.List[int]]::new()

        # Clean up CIPP Backups
        if ($PSCmdlet.ShouldProcess('CIPPBackup', 'Cleaning up old backups')) {
            $CIPPBackupTable = Get-CippTable -tablename 'CIPPBackup'
            $CutoffFilter = "PartitionKey eq 'CIPPBackup' and Timestamp lt datetime'$CutoffDate'"
            $BlobFilter = "$CutoffFilter and BackupIsBlob eq true"

            # Delete blob files in parallel with pagination
            $BlobResult = Remove-BackupBlobsInParallel -Table $CIPPBackupTable -Filter $BlobFilter -BatchSize 500 -ThrottleLimit 10

            # Delete table-only backups with pagination
            $TableDeletedCount = Remove-TableBackupsInBatches -Table $CIPPBackupTable -Filter $CutoffFilter -BatchSize 1000

            $TotalDeleted = $BlobResult.BlobsDeleted + $TableDeletedCount
            if ($TotalDeleted -gt 0) {
                $DeletedCounts.Add($TotalDeleted)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $TotalDeleted old CIPP backups ($($BlobResult.BlobsDeleted) blobs, $TableDeletedCount table entries)" -Sev 'Info'
                Write-Host "Deleted $TotalDeleted old CIPP backups"
            } else {
                Write-Host 'No old CIPP backups found'
            }
        }

        # Clean up Scheduled/Tenant Backups
        if ($PSCmdlet.ShouldProcess('ScheduledBackup', 'Cleaning up old backups')) {
            $ScheduledBackupTable = Get-CippTable -tablename 'ScheduledBackup'
            $CutoffFilter = "PartitionKey eq 'ScheduledBackup' and Timestamp lt datetime'$CutoffDate'"
            $BlobFilter = "$CutoffFilter and BackupIsBlob eq true"

            # Delete blob files in parallel with pagination
            $BlobResult = Remove-BackupBlobsInParallel -Table $ScheduledBackupTable -Filter $BlobFilter -BatchSize 500 -ThrottleLimit 10

            # Delete table-only backups with pagination
            $TableDeletedCount = Remove-TableBackupsInBatches -Table $ScheduledBackupTable -Filter $CutoffFilter -BatchSize 1000

            $TotalDeleted = $BlobResult.BlobsDeleted + $TableDeletedCount
            if ($TotalDeleted -gt 0) {
                $DeletedCounts.Add($TotalDeleted)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $TotalDeleted old tenant backups ($($BlobResult.BlobsDeleted) blobs, $TableDeletedCount table entries)" -Sev 'Info'
                Write-Host "Deleted $TotalDeleted old tenant backups"
            } else {
                Write-Host 'No old tenant backups found'
            }
        }

        $TotalDeleted = ($DeletedCounts | Measure-Object -Sum).Sum
        Write-LogMessage -API 'BackupRetentionCleanup' -message "Backup cleanup completed. Total backups deleted: $TotalDeleted (retention: $RetentionDays days)" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to run backup cleanup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw
    }
}
