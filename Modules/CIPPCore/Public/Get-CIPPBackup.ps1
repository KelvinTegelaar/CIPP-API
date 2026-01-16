function Get-CIPPBackup {
    [CmdletBinding()]
    param (
        [string]$Type = 'CIPP',
        [string]$TenantFilter,
        [string]$Name,
        [switch]$NameOnly
    )

    Write-Host "Getting backup for $Type with TenantFilter $TenantFilter"
    $Table = Get-CippTable -tablename "$($Type)Backup"

    $Conditions = [System.Collections.Generic.List[string]]::new()
    $Conditions.Add("PartitionKey eq '$($Type)Backup'")

    if ($Name) {
        $Conditions.Add("RowKey eq '$($Name)' or OriginalEntityId eq '$($Name)'")
    }

    if ($NameOnly.IsPresent) {
        if ($Type -ne 'Scheduled') {
            $Table.Property = @('RowKey', 'Timestamp', 'BackupIsBlob')
        } else {
            $Table.Property = @('RowKey', 'Timestamp')
        }
    }

    if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
        $Conditions.Add("RowKey gt '$($TenantFilter)' and RowKey lt '$($TenantFilter)~'")
    }

    $Filter = $Conditions -join ' and '
    $Table.Filter = $Filter
    $Info = Get-CIPPAzDataTableEntity @Table

    if ($NameOnly.IsPresent) {
        $Info = $Info | Where-Object { $_.RowKey -notmatch '-part[0-9]+$' }
    } else {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $Info = $Info | Where-Object { $_.TenantFilter -eq $TenantFilter }
        }
    }

    # Augment results with blob-link awareness and fetch blob content when needed
    if (-not $NameOnly.IsPresent -and $Info) {
        foreach ($item in $Info) {
            $isBlobLink = $false
            $blobPath = $null
            if ($null -ne $item.PSObject.Properties['Backup']) {
                $b = $item.Backup
                if ($b -is [string] -and ($b -like 'https://*' -or $b -like 'http://*')) {
                    $isBlobLink = $true
                    $blobPath = $b

                    # Fetch the actual backup content from blob storage
                    try {
                        # Extract container/blob path from URL
                        $resourcePath = $blobPath
                        if ($resourcePath -like '*:10000/*') {
                            # Azurite format: http://host:10000/devstoreaccount1/container/blob
                            $parts = $resourcePath -split ':10000/'
                            if ($parts.Count -gt 1) {
                                # Remove account name to get container/blob
                                $resourcePath = ($parts[1] -split '/', 2)[-1]
                            }
                        } elseif ($resourcePath -like '*blob.core.windows.net/*') {
                            # Azure Storage format: https://account.blob.core.windows.net/container/blob
                            $resourcePath = ($resourcePath -split '.blob.core.windows.net/', 2)[-1]
                        }

                        # Download the blob content
                        $ConnectionString = $env:AzureWebJobsStorage
                        $blobResponse = New-CIPPAzStorageRequest -Service 'blob' -Resource $resourcePath -Method 'GET' -ConnectionString $ConnectionString

                        if ($blobResponse -and $blobResponse.Bytes) {
                            $backupContent = [System.Text.Encoding]::UTF8.GetString($blobResponse.Bytes)
                            # Replace the URL with the actual backup content
                            $item.Backup = $backupContent
                            Write-Verbose "Successfully retrieved backup content from blob storage for $($item.RowKey)"
                        } else {
                            Write-Warning "Failed to retrieve backup content from blob storage for $($item.RowKey)"
                        }
                    } catch {
                        Write-Warning "Error fetching backup from blob storage: $($_.Exception.Message)"
                        # Leave the URL in place if we can't fetch the content
                    }
                }
            }
            $item | Add-Member -NotePropertyName 'BackupIsBlobLink' -NotePropertyValue $isBlobLink -Force
            $item | Add-Member -NotePropertyName 'BlobResourcePath' -NotePropertyValue $blobPath -Force
        }
    }
    return $Info
}
