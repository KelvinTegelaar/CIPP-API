function Start-BackupRetentionCleanup {
    <#
    .SYNOPSIS
    Start the Backup Retention Cleanup Timer
    .DESCRIPTION
    This function cleans up old CIPP and Tenant backups based on the retention policy
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

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

            # Delete blob files
            $BlobFilter = "$CutoffFilter and BackupIsBlob eq true"
            $BlobBackups = Get-AzDataTableEntity @CIPPBackupTable -Filter $BlobFilter -Property @('PartitionKey', 'RowKey', 'Backup')

            $BlobDeletedCount = 0
            if ($BlobBackups) {
                foreach ($Backup in $BlobBackups) {
                    if ($Backup.Backup) {
                        try {
                            $BlobPath = $Backup.Backup
                            # Extract container/blob path from URL
                            if ($BlobPath -like '*:10000/*') {
                                # Azurite format: http://host:10000/devstoreaccount1/container/blob
                                $parts = $BlobPath -split ':10000/'
                                if ($parts.Count -gt 1) {
                                    # Remove account name to get container/blob
                                    $BlobPath = ($parts[1] -split '/', 2)[-1]
                                }
                            } elseif ($BlobPath -like '*blob.core.windows.net/*') {
                                # Azure Storage format: https://account.blob.core.windows.net/container/blob
                                $BlobPath = ($BlobPath -split '.blob.core.windows.net/', 2)[-1]
                            }
                            $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $BlobPath -Method 'DELETE' -ConnectionString $ConnectionString
                            $BlobDeletedCount++
                            Write-Host "Deleted blob: $BlobPath"
                        } catch {
                            Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete blob $($Backup.Backup): $($_.Exception.Message)" -Sev 'Warning'
                        }
                    }
                }
                # Delete blob table entities
                Remove-AzDataTableEntity @CIPPBackupTable -Entity $BlobBackups -Force
            }

            # Delete table-only backups (no blobs)
            # Fetch all old entries and filter out blob entries client-side (null check is unreliable in filters)
            $AllOldBackups = Get-AzDataTableEntity @CIPPBackupTable -Filter $CutoffFilter -Property @('PartitionKey', 'RowKey', 'ETag', 'BackupIsBlob')
            $TableBackups = $AllOldBackups | Where-Object { $_.BackupIsBlob -ne $true }

            $TableDeletedCount = 0
            if ($TableBackups) {
                Remove-AzDataTableEntity @CIPPBackupTable -Entity $TableBackups -Force
                $TableDeletedCount = ($TableBackups | Measure-Object).Count
            }

            $TotalDeleted = $BlobDeletedCount + $TableDeletedCount
            if ($TotalDeleted -gt 0) {
                $DeletedCounts.Add($TotalDeleted)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $TotalDeleted old CIPP backups ($BlobDeletedCount blobs, $TableDeletedCount table entries)" -Sev 'Info'
                Write-Host "Deleted $TotalDeleted old CIPP backups"
            } else {
                Write-Host 'No old CIPP backups found'
            }
        }

        # Clean up Scheduled/Tenant Backups
        if ($PSCmdlet.ShouldProcess('ScheduledBackup', 'Cleaning up old backups')) {
            $ScheduledBackupTable = Get-CippTable -tablename 'ScheduledBackup'
            $CutoffFilter = "PartitionKey eq 'ScheduledBackup' and Timestamp lt datetime'$CutoffDate'"

            # Delete blob files
            $BlobFilter = "$CutoffFilter and BackupIsBlob eq true"
            $BlobBackups = Get-AzDataTableEntity @ScheduledBackupTable -Filter $BlobFilter -Property @('PartitionKey', 'RowKey', 'Backup')

            $BlobDeletedCount = 0
            if ($BlobBackups) {
                foreach ($Backup in $BlobBackups) {
                    if ($Backup.Backup) {
                        try {
                            $BlobPath = $Backup.Backup
                            # Extract container/blob path from URL
                            if ($BlobPath -like '*:10000/*') {
                                # Azurite format: http://host:10000/devstoreaccount1/container/blob
                                $parts = $BlobPath -split ':10000/'
                                if ($parts.Count -gt 1) {
                                    # Remove account name to get container/blob
                                    $BlobPath = ($parts[1] -split '/', 2)[-1]
                                }
                            } elseif ($BlobPath -like '*blob.core.windows.net/*') {
                                # Azure Storage format: https://account.blob.core.windows.net/container/blob
                                $BlobPath = ($BlobPath -split '.blob.core.windows.net/', 2)[-1]
                            }
                            $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $BlobPath -Method 'DELETE' -ConnectionString $ConnectionString
                            $BlobDeletedCount++
                            Write-Host "Deleted blob: $BlobPath"
                        } catch {
                            Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete blob $($Backup.Backup): $($_.Exception.Message)" -Sev 'Warning'
                        }
                    }
                }
                # Delete blob table entities
                Remove-AzDataTableEntity @ScheduledBackupTable -Entity $BlobBackups -Force
            }

            # Delete table-only backups (no blobs)
            # Fetch all old entries and filter out blob entries client-side (null check is unreliable in filters)
            $AllOldBackups = Get-AzDataTableEntity @ScheduledBackupTable -Filter $CutoffFilter -Property @('PartitionKey', 'RowKey', 'ETag', 'BackupIsBlob')
            $TableBackups = $AllOldBackups | Where-Object { $_.BackupIsBlob -ne $true }

            $TableDeletedCount = 0
            if ($TableBackups) {
                Remove-AzDataTableEntity @ScheduledBackupTable -Entity $TableBackups -Force
                $TableDeletedCount = ($TableBackups | Measure-Object).Count
            }

            $TotalDeleted = $BlobDeletedCount + $TableDeletedCount
            if ($TotalDeleted -gt 0) {
                $DeletedCounts.Add($TotalDeleted)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $TotalDeleted old tenant backups ($BlobDeletedCount blobs, $TableDeletedCount table entries)" -Sev 'Info'
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
