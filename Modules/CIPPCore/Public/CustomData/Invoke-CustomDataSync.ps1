function Invoke-CustomDataSync {
    param(
        $TenantFilter
    )

    $Table = Get-CIPPTable -TableName CustomDataMappings
    $CustomData = Get-CIPPAzDataTableEntity @Table

    $Mappings = $CustomData | ForEach-Object {
        $Mapping = $_.JSON | ConvertFrom-Json
        $Mapping
    }

    Write-Information "Found $($Mappings.Count) Custom Data mappings"
    $Mappings = $Mappings | Where-Object { $_.sourceType.value -eq 'extensionSync' -and $_.tenantFilter.value -contains $TenantFilter -or $_.tenantFilter.value -contains 'AllTenants' }

    if ($Mappings.Count -eq 0) {
        Write-Warning "No Custom Data mappings found for tenant $TenantFilter"
        return
    }

    Write-Information "Getting cached data for tenant $TenantFilter"
    $Cache = Get-ExtensionCacheData -TenantFilter $TenantFilter
    $BulkRequests = [System.Collections.Generic.List[object]]::new()
    $DirectoryObjectQueries = [System.Collections.Generic.List[object]]::new()
    $SyncConfigs = foreach ($Mapping in $Mappings) {
        $SyncConfig = [PSCustomObject]@{
            Dataset                   = $Mapping.extensionSyncDataset.value
            DatasetConfig             = $Mapping.extensionSyncDataset.addedFields
            DirectoryObjectType       = $Mapping.directoryObjectType.value
            ExtensionSyncProperty     = $Mapping.extensionSyncProperty.value
            CustomDataAttribute       = $Mapping.customDataAttribute.value
            CustomDataAttributeConfig = $Mapping.customDataAttribute.addedFields
        }

        switch ($SyncConfig.DirectoryObjectType) {
            'user' {
                $Query = @{
                    id     = 'user'
                    url    = 'users?$select=id,userPrincipalName,displayName&$count=true&$top=999'
                    method = 'GET'
                }
            }
        }
        $DirectoryObjectQueries.Add($Query)
        $SyncConfig
    }

    Write-Information "Getting directory objects for tenant $TenantFilter"
    #Write-Information ($DirectoryObjectQueries | ConvertTo-Json -Depth 10)
    $AllDirectoryObjects = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($DirectoryObjectQueries)

    foreach ($SyncConfig in $SyncConfigs) {
        Write-Warning "Processing Custom Data mapping for $($Mapping.customDataAttribute.value)"
        Write-Information ($SyncConfig | ConvertTo-Json -Depth 10)
        $Rows = $Cache.$($SyncConfig.Dataset)
        if (!$Rows) {
            Write-Warning "No data found for dataset $($SyncConfig.Dataset)"
            continue
        }
        $SourceMatchProperty = $SyncConfig.DatasetConfig.sourceMatchProperty
        $DestinationMatchProperty = $SyncConfigs.DatasetConfig.destinationMatchProperty
        $CustomDataAttribute = $SyncConfig.CustomDataAttribute
        $ExtensionSyncProperty = $SyncConfig.ExtensionSyncProperty
        $DatasetConfig = $SyncConfig.DatasetConfig

        $DirectoryObjects = ($AllDirectoryObjects | Where-Object { $_.id -eq $SyncConfig.DirectoryObjectType }).body.value

        switch ($SyncConfig.DirectoryObjectType) {
            'user' {
                $url = 'users'
            }
        }

        foreach ($Row in $Rows) {
            #Write-Warning 'Processing row'
            #Write-Information ($Row | ConvertTo-Json -Depth 10)
            #Write-Host "Comparing $SourceMatchProperty $($Row.$SourceMatchProperty) to $($DirectoryObjects.Count) directory objects on $DestinationMatchProperty"
            $DirectoryObject = $DirectoryObjects | Where-Object { $_.$DestinationMatchProperty -eq $Row.$SourceMatchProperty }
            if (!$DirectoryObject) {
                Write-Warning "No directory object found for $($Row.$SourceMatchProperty)"
            }
            if ($DirectoryObject) {
                $ObjectUrl = "$($url)/$($DirectoryObject.id)"

                if ($DatasetConfig.type -eq 'object') {
                    if ($CustomDataAttribute -match '\.') {
                        $Props = @($CustomDataAttribute -split '\.')
                        $Body = [PSCustomObject]@{
                            $Props[0] = [PSCustomObject]@{
                                $Props[1] = $Row.$ExtensionSyncProperty
                            }
                        }
                    } else {
                        $Body = [PSCustomObject]@{
                            $CustomDataAttribute = @($Row.$ExtensionSyncProperty)
                        }
                    }
                } elseif ($DatasetConfig.type -eq 'array') {

                    $Data = foreach ($Entry in $Row.$ExtensionSyncProperty) {
                        if ($DatasetConfig.storeAs -eq 'json') {
                            $Entry | ConvertTo-Json -Depth 5 -Compress
                        } else {
                            $Entry
                        }
                    }

                    $Body = [PSCustomObject]@{
                        $CustomDataAttribute = @($Data)
                    }
                }

                $BulkRequests.Add([PSCustomObject]@{
                        id      = $DirectoryObject.$DestinationMatchProperty
                        url     = $ObjectUrl
                        method  = 'PATCH'
                        headers = @{
                            'Content-Type' = 'application/json'
                        }
                        body    = $Body.PSObject.Copy()
                    })
            }
        }
    }

    #Write-Host ($BulkRequests | ConvertTo-Json -Depth 10)
    if ($BulkRequests.Count -gt 0) {
        Write-Information "Sending $($BulkRequests.Count) requests to Graph API"
        $Responses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests)
        if ($Responses | Where-Object { $_.statusCode -ne 204 }) {
            Write-Warning 'Some requests failed'
            Write-Information ($Responses | Where-Object { $_.statusCode -ne 204 } | Select-Object -Property id, statusCode | ConvertTo-Json)
        }
    }
}
