function New-CIPPBackup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $backupType,
        $StorageOutput = 'default',
        $TenantFilter,
        $ScheduledBackupValues,
        $APIName = 'CIPP Backup',
        $Headers
    )

    $BackupData = switch ($backupType) {
        #If backup type is CIPP, create CIPP backup.
        'CIPP' {
            try {
                $BackupTables = @(
                    'AppPermissions'
                    'AccessRoleGroups'
                    'ApiClients'
                    'CippReplacemap'
                    'CustomData'
                    'CustomRoles'
                    'Config'
                    'CommunityRepos'
                    'Domains'
                    'GraphPresets'
                    'GDAPRoles'
                    'GDAPRoleTemplates'
                    'ExcludedLicenses'
                    'templates'
                    'standards'
                    'SchedulerConfig'
                    'Extensions'
                    'WebhookRules'
                    'ScheduledTasks'
                    'TenantProperties'
                )
                $CSVfile = foreach ($CSVTable in $BackupTables) {
                    $Table = Get-CippTable -tablename $CSVTable
                    Get-AzDataTableEntity @Table | Select-Object * -ExcludeProperty DomainAnalyser, table, Timestamp, ETag, Results | Select-Object *, @{l = 'table'; e = { $CSVTable } }
                }
                $RowKey = 'CIPPBackup' + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
                $CSVfile
                $CSVFile = [string]($CSVfile | ConvertTo-Json -Compress -Depth 100)
                $entity = @{
                    PartitionKey = 'CIPPBackup'
                    RowKey       = [string]$RowKey
                    TenantFilter = 'CIPPBackup'
                    Backup       = $CSVfile
                }
                $Table = Get-CippTable -tablename 'CIPPBackup'
                try {
                    if ($PSCmdlet.ShouldProcess('CIPP Backup', 'Create')) {
                        $null = Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                        Write-LogMessage -headers $Headers -API $APINAME -message 'Created CIPP Backup' -Sev 'Debug'
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup for CIPP: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                    [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
                }

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
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
            Write-Information "Scheduled backup value psproperties: $(([pscustomobject]$ScheduledBackupValues).psobject.Properties)"
            foreach ($ScheduledBackup in ([pscustomobject]$ScheduledBackupValues).psobject.Properties.Name) {
                try {
                    $BackupResult = New-CIPPBackupTask -Task $ScheduledBackup -TenantFilter $TenantFilter | ConvertTo-Json -Depth 100 -Compress | Out-String
                    $entity[$ScheduledBackup] = "$BackupResult"
                } catch {
                    Write-Information "Failed to create backup for $ScheduledBackup - $($_.Exception.Message)"
                }
            }
            $Table = Get-CippTable -tablename 'ScheduledBackup'
            try {
                measure-cipptask -TaskName 'ScheduledBackupStorage' -EventName 'CIPP.BackupCompleted' -Script {
                    $null = Add-CIPPAzDataTableEntity @Table -entity $entity -Force
                }
                Write-LogMessage -headers $Headers -API $APINAME -message 'Created backup' -Sev 'Debug'
                $State = 'Backup finished successfully'
            } catch {
                $State = 'Failed to write backup to table storage'
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create tenant backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
            }
        }

    }
    return @([pscustomobject]@{
            BackupName  = $RowKey
            BackupState = $State
        })
}

