function New-CIPPBackup {
    [CmdletBinding()]
    param (
        $backupType,
        $StorageOutput = 'default',
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
                    Get-CIPPAzDataTableEntity @Table
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
        'ConditionalAccess' { 
            $ConditionalAccessPolicyOutput = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $tenantfilter
            $AllNamedLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $tenantfilter
            switch ($StorageOutput) {
                'default' {
                    [PSCustomObject]@{
                        ConditionalAccessPolicies = $ConditionalAccessPolicyOutput
                        NamedLocations            = $AllNamedLocations
                    }
                }
                'table' {
                    #Store output in tablestorage for Recovery
                    $RowKey = $TenantFilter + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
                    $entity = [PSCustomObject]@{
                        PartitionKey   = 'ConditionalAccessBackup'
                        RowKey         = $RowKey
                        TenantFilter   = $TenantFilter
                        Policies       = [string]($ConditionalAccessPolicyOutput | ConvertTo-Json -Compress -Depth 10)
                        NamedLocations = [string]($AllNamedLocations | ConvertTo-Json -Compress -Depth 10)
                    }
                    $Table = Get-CippTable -tablename 'ConditionalAccessBackup'
                    try {
                        $Result = Add-CIPPAzDataTableEntity @Table -entity $entity -Force
                        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Created backup for Conditional Access Policies' -Sev 'Debug'
                        $Result
                    } catch {
                        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create backup for Conditional Access Policies: $($_.Exception.Message)" -Sev 'Error'
                        [pscustomobject]@{'Results' = "Backup Creation failed: $($_.Exception.Message)" }
                    }
                }
            }
        }

    }
    return $BackupData
}

