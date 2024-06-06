function New-CIPPBackup {
    [CmdletBinding()]
    param (
        $backupType,
        $TenantFilter,
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
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup: $($_.Exception.Message)" -Sev 'Error'
                $body = [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
            }
        }
    }
    return $BackupData
}

