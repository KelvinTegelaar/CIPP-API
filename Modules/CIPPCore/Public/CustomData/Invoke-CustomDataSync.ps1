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
                    url    = 'users?$select=id,userPrincipalName,displayName,mailNickname&$count=true&$top=999'
                    method = 'GET'
                }
            }
        }
        $SyncConfig
        if ($DirectoryObjectQueries | Where-Object { $_.id -eq $Query.id }) {
            continue
        } else {
            $DirectoryObjectQueries.Add($Query)
        }
    }

    Write-Information "Getting directory objects for tenant $TenantFilter"
    #Write-Information ($DirectoryObjectQueries | ConvertTo-Json -Depth 10)
    $AllDirectoryObjects = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($DirectoryObjectQueries)
    Write-Information "Retrieved $($AllDirectoryObjects.Count) result sets"
    #Write-Information ($AllDirectoryObjects | ConvertTo-Json -Depth 10)

    $PatchObjects = @{}

    foreach ($SyncConfig in $SyncConfigs) {
        Write-Warning "Processing Custom Data mapping for $($SyncConfig.Dataset)"
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
            Write-Host "Comparing $SourceMatchProperty $($Row.$SourceMatchProperty) to $($DirectoryObjects.Count) directory objects on $DestinationMatchProperty"
            if ($DestinationMatchProperty.Count -gt 1) {
                foreach ($Prop in $DestinationMatchProperty) {
                    $DirectoryObject = $DirectoryObjects | Where-Object { $_.$Prop -eq $Row.$SourceMatchProperty }
                    if ($DirectoryObject) {
                        break
                    }
                }
            } else {
                $DirectoryObject = $DirectoryObjects | Where-Object { $_.$DestinationMatchProperty -eq $Row.$SourceMatchProperty }
            }

            if (!$DirectoryObject) {
                Write-Warning "No directory object found for $($Row.$SourceMatchProperty)"
            }
            if ($DirectoryObject) {
                $ObjectUrl = "$($url)/$($DirectoryObject.id)"

                # check if key in patch objects already exists otherwise create one with object url
                if (!$PatchObjects.ContainsKey($ObjectUrl)) {
                    Write-Host "Creating new object for $($ObjectUrl)"
                    $PatchObjects[$ObjectUrl] = @{}
                }

                if ($DatasetConfig.type -eq 'object') {
                    if ($CustomDataAttribute -match '\.') {
                        $Props = @($CustomDataAttribute -split '\.')
                        if (!$PatchObjects[$ObjectUrl].ContainsKey($Props[0])) {
                            Write-Host "Creating new object for $($Props[0])"
                            $PatchObjects[$ObjectUrl][$Props[0]] = @{}
                        }
                        if (!$PatchObjects[$ObjectUrl][$Props[0]].ContainsKey($Props[1])) {
                            Write-Host "Creating new object for $($Props[1])"
                            $PatchObjects[$ObjectUrl][$Props[0]][$Props[1]] = $Row.$ExtensionSyncProperty
                        }
                    } else {
                        $PatchObjects[$ObjectUrl][$CustomDataAttribute] = $Row.$ExtensionSyncProperty
                    }
                } elseif ($DatasetConfig.type -eq 'array') {
                    Write-Warning "Processing array data for $($CustomDataAttribute) on $($DirectoryObject.id) - found $($Row.Count) entries"
                    #Write-Information ($Row | ConvertTo-Json -Depth 10)
                    if ($DatasetConfig.select) {
                        $Row = $Row | Select-Object -Property ($DatasetConfig.select -split ',')
                    }

                    if (!$PatchObjects[$ObjectUrl].ContainsKey($CustomDataAttribute)) {
                        $PatchObjects[$ObjectUrl][$CustomDataAttribute] = [System.Collections.Generic.List[string]]::new()
                    }

                    $Data = if ($DatasetConfig.storeAs -eq 'json') {
                        $Row | ConvertTo-Json -Depth 5 -Compress
                    } else {
                        $Row
                    }

                    $PatchObjects[$ObjectUrl][$CustomDataAttribute].Add($Data)
                }
            }
        }
    }

    foreach ($ObjectUrl in $PatchObjects.Keys) {
        $PatchObject = $PatchObjects[$ObjectUrl]
        $BulkRequests.Add([PSCustomObject]@{
                id      = ($ObjectUrl -split '/' | Select-Object -Last 1)
                url     = $ObjectUrl
                method  = 'PATCH'
                body    = $PatchObject
                headers = @{
                    'Content-Type' = 'application/json'
                }
            })
    }

    Write-Host ($BulkRequests | ConvertTo-Json -Depth 10)
    if ($BulkRequests.Count -gt 0) {
        Write-Information "Sending $($BulkRequests.Count) requests to Graph API"
        $Responses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests)
        if ($Responses | Where-Object { $_.statusCode -ne 204 }) {
            Write-Warning 'Some requests failed'
            Write-Information ($Responses | Where-Object { $_.status -ne 204 } | ConvertTo-Json -Depth 10)
        }
    }
}
