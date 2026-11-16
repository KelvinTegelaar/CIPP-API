function Start-BackupRetentionCleanup {
    <#
    .SYNOPSIS
    Start the Backup Retention Cleanup Timer
    .DESCRIPTION
    This function cleans up old CIPP and Tenant backups based on the retention policy
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage
    )

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

        foreach ($Target in @(@{ Table = 'CIPPBackup'; Label = 'CIPP' }, @{ Table = 'ScheduledBackup'; Label = 'tenant' })) {
            if (-not $PSCmdlet.ShouldProcess($Target.Table, 'Cleaning up old backups')) { continue }
            $BackupTable = Get-CippTable -tablename $Target.Table
            $CutoffFilter = "PartitionKey eq '$($Target.Table)' and Timestamp lt datetime'$CutoffDate'"
            $BlobDeletedCount = 0
            $TableDeletedCount = 0

            # A page at a time, so a run that times out keeps what it deleted
            do {
                $Page = @(Get-AzDataTableEntity @BackupTable -Filter "$CutoffFilter and BackupIsBlob eq true" -Property @('PartitionKey', 'RowKey', 'ETag', 'Backup') -First 1000)
                foreach ($Backup in $Page) {
                    if (-not $Backup.Backup) { continue }
                    try {
                        $BlobPath = $Backup.Backup
                        if ($BlobPath -like '*:10000/*') {
                            # Azurite format: http://host:10000/devstoreaccount1/container/blob
                            $BlobPath = (($BlobPath -split ':10000/')[1] -split '/', 2)[-1]
                        } elseif ($BlobPath -like '*blob.core.windows.net/*') {
                            $BlobPath = ($BlobPath -split '.blob.core.windows.net/', 2)[-1]
                        }
                        $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $BlobPath -Method 'DELETE' -ConnectionString $ConnectionString
                        $BlobDeletedCount++
                    } catch {
                        Write-LogMessage -API 'BackupRetentionCleanup' -message "Failed to delete blob $($Backup.Backup): $($_.Exception.Message)" -sev 'Warning'
                    }
                }
                if ($Page.Count -gt 0) {
                    Remove-AzDataTableEntity @BackupTable -Entity $Page -Force
                }
            } while ($Page.Count -eq 1000)

            # Table-only backups; their part rows share the backup's age, so they match the same filter
            do {
                $Page = @(Get-AzDataTableEntity @BackupTable -Filter $CutoffFilter -Property @('PartitionKey', 'RowKey', 'ETag') -First 1000)
                if ($Page.Count -gt 0) {
                    Remove-AzDataTableEntity @BackupTable -Entity $Page -Force
                    $TableDeletedCount += $Page.Count
                }
            } while ($Page.Count -eq 1000)

            $TotalDeleted = $BlobDeletedCount + $TableDeletedCount
            if ($TotalDeleted -gt 0) {
                $DeletedCounts.Add($TotalDeleted)
                Write-LogMessage -API 'BackupRetentionCleanup' -message "Deleted $TotalDeleted old $($Target.Label) backups ($BlobDeletedCount blobs, $TableDeletedCount table entries)" -Sev 'Info'
                Write-Host "Deleted $TotalDeleted old $($Target.Label) backups"
            } else {
                Write-Host "No old $($Target.Label) backups found"
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
