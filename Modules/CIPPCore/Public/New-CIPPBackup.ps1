function New-CIPPBackup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('CIPP', 'Scheduled')]
        [string]$backupType,

        $StorageOutput = 'default',

        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        $ScheduledBackupValues,
        $APIName = 'CIPP Backup',
        $Headers,
        [Parameter(Mandatory = $false)] [string] $ConnectionString = $env:AzureWebJobsStorage
    )

    # Validate that TenantFilter is provided for Scheduled backups
    if ($backupType -eq 'Scheduled' -and [string]::IsNullOrEmpty($TenantFilter)) {
        throw 'TenantFilter is required for Scheduled backups'
    }

    $State = 'Backup finished successfully'
    $RowKey = $null
    $BackupData = $null
    $TableName = $null
    $PartitionKey = $null
    $ContainerName = $null

    try {
        switch ($backupType) {
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
                    $BackupData = [string]($CSVfile | ConvertTo-Json -Compress -Depth 100)
                    $TableName = 'CIPPBackup'
                    $PartitionKey = 'CIPPBackup'
                    $ContainerName = 'cipp-backups'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                    return [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
                }
            }

            #If Backup type is Scheduled, create Scheduled backup.
            'Scheduled' {
                try {
                    $RowKey = $TenantFilter + '_' + (Get-Date).ToString('yyyy-MM-dd-HHmm')
                    $entity = @{
                        PartitionKey = 'ScheduledBackup'
                        RowKey       = $RowKey
                        TenantFilter = $TenantFilter
                    }
                    Write-Information "Scheduled backup value psproperties: $(([pscustomobject]$ScheduledBackupValues).psobject.Properties)"
                    foreach ($ScheduledBackup in ([pscustomobject]$ScheduledBackupValues).psobject.Properties.Name) {
                        try {
                            $BackupResult = New-CIPPBackupTask -Task $ScheduledBackup -TenantFilter $TenantFilter
                            $entity[$ScheduledBackup] = $BackupResult
                        } catch {
                            Write-Information "Failed to create backup for $ScheduledBackup - $($_.Exception.Message)"
                        }
                    }
                    $BackupData = $entity | ConvertTo-Json -Compress -Depth 100
                    $TableName = 'ScheduledBackup'
                    $PartitionKey = 'ScheduledBackup'
                    $ContainerName = 'scheduled-backups'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                    return [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }

        # Upload backup data to blob storage
        $blobUrl = $null
        try {
            $containers = @()
            try { $containers = New-CIPPAzStorageRequest -Service 'blob' -Component 'list' -ConnectionString $ConnectionString } catch { $containers = @() }
            $exists = ($containers | Where-Object { $_.Name -eq $ContainerName }) -ne $null
            if (-not $exists) {
                $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $ContainerName -Method 'PUT' -QueryParams @{ restype = 'container' } -ConnectionString $ConnectionString
                Start-Sleep -Milliseconds 500
            }
            $blobName = "$RowKey.json"
            $resourcePath = "$ContainerName/$blobName"
            $null = New-CIPPAzStorageRequest -Service 'blob' -Resource $resourcePath -Method 'PUT' -ContentType 'application/json; charset=utf-8' -Body $BackupData -ConnectionString $ConnectionString

            # Build full blob URL for storage in table
            try {
                $csParts = @{}
                foreach ($p in ($ConnectionString -split ';')) {
                    if (-not [string]::IsNullOrWhiteSpace($p)) {
                        $kv = $p -split '=', 2
                        if ($kv.Length -eq 2) { $csParts[$kv[0]] = $kv[1] }
                    }
                }

                # Handle UseDevelopmentStorage=true (Azurite)
                if ($csParts.ContainsKey('UseDevelopmentStorage') -and $csParts['UseDevelopmentStorage'] -eq 'true') {
                    $base = 'http://127.0.0.1:10000/devstoreaccount1'
                } elseif ($csParts.ContainsKey('BlobEndpoint') -and $csParts['BlobEndpoint']) {
                    $base = ($csParts['BlobEndpoint']).TrimEnd('/')
                } else {
                    $protocol = if ($csParts.ContainsKey('DefaultEndpointsProtocol') -and $csParts['DefaultEndpointsProtocol']) { $csParts['DefaultEndpointsProtocol'] } else { 'https' }
                    $suffix = if ($csParts.ContainsKey('EndpointSuffix') -and $csParts['EndpointSuffix']) { $csParts['EndpointSuffix'] } else { 'core.windows.net' }
                    $acct = $csParts['AccountName']
                    if (-not $acct) { throw 'AccountName missing in ConnectionString' }
                    $base = "$protocol`://$acct.blob.$suffix"
                }
                $blobUrl = "$base/$resourcePath"
            } catch {
                # If building full URL fails, fall back to resource path
                $blobUrl = $resourcePath
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APINAME -message "Blob upload failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }

        # Write table entity pointing to blob resource
        $entity = @{
            PartitionKey = $PartitionKey
            RowKey       = [string]$RowKey
            Backup       = $blobUrl
            BackupIsBlob = $true
        }

        if ($TenantFilter) {
            $entity['TenantFilter'] = $TenantFilter
        }

        $Table = Get-CippTable -tablename $TableName
        try {
            if ($PSCmdlet.ShouldProcess("$backupType Backup", 'Create')) {
                $null = Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                Write-LogMessage -headers $Headers -API $APINAME -message "Created $backupType Backup (link stored)" -Sev 'Debug'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup for $backupType : $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            return [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -message "Failed to create backup: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return [pscustomobject]@{'Results' = "Backup Creation failed: $($ErrorMessage.NormalizedError)" }
    }

    return [pscustomobject]@{
        BackupName  = $RowKey
        BackupState = $State
    }
}

