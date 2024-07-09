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
                    'bpa'
                    'Config'
                    'Domains'
                    'ExcludedLicenses'
                    'templates'
                    'standards'
                    'SchedulerConfig'
                )
                $CSVfile = foreach ($CSVTable in $BackupTables) {
                    $Table = Get-CippTable -tablename $CSVTable
                    Get-CIPPAzDataTableEntity @Table | Select-Object *, @{l = 'table'; e = { $CSVTable } }
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup' -Sev 'Debug'
                $CSVfile
                $RowKey = 'CIPPBackup' + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
                $entity = [PSCustomObject]@{
                    PartitionKey = 'CIPPBackup'
                    RowKey       = $RowKey
                    TenantFilter = 'CIPPBackup'
                    Backup       = [string]($CSVfile | ConvertTo-Json -Compress -Depth 100)
                }
                $Table = Get-CippTable -tablename 'CIPPBackup'
                try {
                    $Result = Add-CIPPAzDataTableEntity @Table -entity $entity -Force
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created CIPP Backup' -Sev 'Debug'
                } catch {
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup for CIPP: $($_.Exception.Message)" -Sev 'Error'
                    [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
                }

            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup: $($_.Exception.Message)" -Sev 'Error'
                [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
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
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup for Conditional Access Policies: $($_.Exception.Message)" -Sev 'Error'
                [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
            }
        }

    }
    return [pscustomobject]@{
        BackupName  = $RowKey
        BackupState = $State
        BackupData  = $BackupData
    }
}

