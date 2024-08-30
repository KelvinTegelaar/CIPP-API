function New-CIPPBackup {
    [CmdletBinding()]
    param (
        $backupType,
        $StorageOutput = 'default',
        $TenantFilter,
        $ScheduledBackupValues,
        $APIName = 'CIPP Backup',
        $ExecutingUser
    )

    $BackupData = switch ($backupType) {
        #If backup type is CIPP, create CIPP backup.
        'CIPP' {
            try {
                $BackupTables = @(
                    'Config'
                    'Domains'
                    'ExcludedLicenses'
                    'templates'
                    'standards'
                    'SchedulerConfig'
                    'Extensions'
                )
                $CSVfile = foreach ($CSVTable in $BackupTables) {
                    $Table = Get-CippTable -tablename $CSVTable
                    Get-AzDataTableEntity @Table | Select-Object *, @{l = 'table'; e = { $CSVTable } } -ExcludeProperty DomainAnalyser
                }
                $RowKey = 'CIPPBackup' + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
                $CSVFile = [string]($CSVfile | ConvertTo-Json -Compress -Depth 100)
                $entity = @{
                    PartitionKey = 'CIPPBackup'
                    RowKey       = [string]$RowKey
                    TenantFilter = 'CIPPBackup'
                    Backup       = $CSVfile
                }
                $Table = Get-CippTable -tablename 'CIPPBackup'
                try {
                    $Result = Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created CIPP Backup' -Sev 'Debug'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup for CIPP: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                    [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
                }

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
            }
        }

        #If Backup type is ConditionalAccess, create Conditional Access backup.
        'Scheduled' {
            #Do a sub switch here based on the ScheduledBackupValues?
            #Store output in tablestorage for Recovery
            $RowKey = $TenantFilter + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
            $entity = @{
                PartitionKey = 'ScheduledBackup'
                RowKey       = $RowKey
                TenantFilter = $TenantFilter
            }
            Write-Host "Scheduled backup value psproperties: $(([pscustomobject]$ScheduledBackupValues).psobject.Properties)"
            foreach ($ScheduledBackup in ([pscustomobject]$ScheduledBackupValues).psobject.Properties.Name) {
                $BackupResult = New-CIPPBackupTask -Task $ScheduledBackup -TenantFilter $TenantFilter | ConvertTo-Json -Depth 100 -Compress | Out-String
                $entity[$ScheduledBackup] = "$BackupResult"
            }
            $Table = Get-CippTable -tablename 'ScheduledBackup'
            try {
                $Result = Add-CIPPAzDataTableEntity @Table -entity $entity -Force
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup' -Sev 'Debug'
                $State = 'Backup finished succesfully'
                $Result
            } catch {
                $State = 'Failed to write backup to table storage'
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup for Conditional Access Policies: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
            }
        }

    }
    return [pscustomobject]@{
        BackupName  = $RowKey
        BackupState = $State
        BackupData  = $BackupData
    }
}

