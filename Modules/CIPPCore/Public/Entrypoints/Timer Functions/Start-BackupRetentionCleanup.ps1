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
            $Filter = "PartitionKey eq 'CIPPBackup' and Timestamp lt datetime'$CutoffDate'"
            
            $OldCIPPBackups = Get-AzDataTableEntity @CIPPBackupTable -Filter $Filter -Property @('PartitionKey', 'RowKey', 'ETag')
            
            if ($OldCIPPBackups) {
                Write-Host "Found $($OldCIPPBackups.Count) old CIPP backups to delete"
                Remove-AzDataTableEntity @CIPPBackupTable -Entity $OldCIPPBackups -Force
                $DeletedCounts.Add($OldCIPPBackups.Count)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $($OldCIPPBackups.Count) old CIPP backups" -Sev 'Info'
            } else {
                Write-Host 'No old CIPP backups found'
            }
        }

        # Clean up Scheduled/Tenant Backups
        if ($PSCmdlet.ShouldProcess('ScheduledBackup', 'Cleaning up old backups')) {
            $ScheduledBackupTable = Get-CippTable -tablename 'ScheduledBackup'
            $Filter = "PartitionKey eq 'ScheduledBackup' and Timestamp lt datetime'$CutoffDate'"
            
            $OldScheduledBackups = Get-AzDataTableEntity @ScheduledBackupTable -Filter $Filter -Property @('PartitionKey', 'RowKey', 'ETag')
            
            if ($OldScheduledBackups) {
                Write-Host "Found $($OldScheduledBackups.Count) old tenant backups to delete"
                Remove-AzDataTableEntity @ScheduledBackupTable -Entity $OldScheduledBackups -Force
                $DeletedCounts.Add($OldScheduledBackups.Count)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $($OldScheduledBackups.Count) old tenant backups" -Sev 'Info'
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
