function Invoke-ExecCustomData {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Action = $Request.Query.Action ?? $Request.Body.Action
    $CustomDataTable = Get-CippTable -TableName 'CustomData'
    $CustomDataMappingsTable = Get-CippTable -TableName 'CustomDataMappings'

    Write-Information "Executing action '$Action'"

    switch ($Action) {
        'ListSchemaExtensions' {
            try {
                $SchemaExtensions = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'" | Select-Object -ExpandProperty JSON | ConvertFrom-Json
                if (!$SchemaExtensions -or $SchemaExtensions.id -notmatch '_') {
                    $SchemaExtensions = Get-CIPPSchemaExtensions | Sort-Object id
                }
                $Body = @{
                    Results = @($SchemaExtensions)
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to retrieve schema extensions: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'AddSchemaExtension' {
            try {
                $SchemaExtension = $Request.Body.schemaExtension
                if (!$SchemaExtension) {
                    throw 'SchemaExtension data is missing in the request body.'
                }

                $Entity = @{
                    PartitionKey = 'SchemaExtension'
                    RowKey       = $SchemaExtension.id
                    JSON         = [string]($SchemaExtension | ConvertTo-Json -Depth 5 -Compress)
                }

                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $Entity -Force
                $SchemaExtensions = Get-CIPPSchemaExtensions | Where-Object { $_.id -eq $SchemaExtension.id }

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Schema extension '$($SchemaExtension.id)' added successfully."
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to add schema extension: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'DeleteSchema' {
            try {
                $SchemaId = $Request.Body.id
                if (!$SchemaId) {
                    throw 'Schema ID is missing in the request body.'
                }

                # Retrieve the schema extension entity
                $SchemaEntity = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'" | Where-Object { $SchemaId -match $_.RowKey }
                if (!$SchemaEntity) {
                    throw "Schema extension with ID '$SchemaId' not found."
                }

                # Ensure the schema is in 'InDevelopment' state before deletion
                $SchemaDefinition = $SchemaEntity.JSON | ConvertFrom-Json
                if ($SchemaDefinition.status -ne 'InDevelopment') {
                    throw "Schema extension '$SchemaId' cannot be deleted because it is not in 'InDevelopment' state."
                }

                try {
                    $null = New-GraphPOSTRequest -Type DELETE -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$SchemaId" -AsApp $true -NoAuthCheck $true -tenantid $env:TenantID -Verbose
                } catch {
                    Write-Warning "Schema extension '$SchemaId' not found in Microsoft Graph."
                }


                # Delete the schema extension entity
                Remove-AzDataTableEntity @CustomDataTable -Entity $SchemaEntity

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Schema extension '$SchemaId' deleted successfully."
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to delete schema extension: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'AddSchemaProperty' {
            try {
                $SchemaId = $Request.Body.id
                $Name = $Request.Body.name
                $Type = $Request.Body.type
                $NewProperty = @{
                    name = $Name
                    type = $Type
                }
                if (!$SchemaId) {
                    throw 'Schema ID is missing in the request body.'
                }
                if (!$Name -or !$Type) {
                    throw 'Property data is missing or incomplete in the request body.'
                }

                # Retrieve the schema extension entity
                $SchemaEntity = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'" | Where-Object { $SchemaId -match $_.RowKey }
                if (!$SchemaEntity) {
                    throw "Schema extension with ID '$SchemaId' not found."
                }

                # Parse the schema definition
                $SchemaDefinition = $SchemaEntity.JSON | ConvertFrom-Json

                if ($SchemaDefinition.status -eq 'Deprecated') {
                    throw "Properties cannot be added to schema extension '$SchemaId' because it is in the 'Deprecated' state."
                }

                # Check if the property already exists
                if ($SchemaDefinition.properties | Where-Object { $_.name -eq $NewProperty.name }) {
                    throw "Property with name '$($NewProperty.name)' already exists in schema extension '$SchemaId'."
                }

                # Add the new property
                $Properties = [System.Collections.Generic.List[object]]::new()
                foreach ($Property in $SchemaDefinition.properties) {
                    $Properties.Add($Property)
                }
                $Properties.Add($NewProperty)
                $SchemaDefinition.properties = $Properties

                # Update the schema extension entity
                $SchemaEntity.JSON = [string]($SchemaDefinition | ConvertTo-Json -Depth 5 -Compress)
                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $SchemaEntity -Force
                try { $null = Get-CIPPSchemaExtensions } catch {}

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Property '$($NewProperty.name)' added to schema extension '$SchemaId' successfully."
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to add property to schema extension: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'ChangeSchemaState' {
            try {
                $SchemaId = $Request.Body.id
                $NewStatus = $Request.Body.status
                if (!$SchemaId) {
                    throw 'Schema ID is missing in the request body.'
                }
                if (!$NewStatus) {
                    throw 'New status is missing in the request body.'
                }

                # Retrieve the schema extension entity
                $SchemaEntity = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'" | Where-Object { $SchemaId -match $_.RowKey }
                if (!$SchemaEntity) {
                    throw "Schema extension with ID '$SchemaId' not found."
                }

                # Parse the schema definition
                $SchemaDefinition = $SchemaEntity.JSON | ConvertFrom-Json

                # Check if the status is already the same
                if ($SchemaDefinition.status -eq $NewStatus) {
                    throw "Schema extension '$SchemaId' is already in the '$NewStatus' state."
                }

                # Update the status
                $SchemaDefinition.status = $NewStatus

                # Update the schema extension entity
                $SchemaEntity.JSON = [string]($SchemaDefinition | ConvertTo-Json -Depth 5 -Compress)
                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $SchemaEntity -Force
                $null = Get-CIPPSchemaExtensions

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Schema extension '$SchemaId' status changed to '$NewStatus' successfully."
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to change schema extension status: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'ListDirectoryExtensions' {
            try {
                $Uri = "https://graph.microsoft.com/beta/applications(appId='$($env:ApplicationID)')/extensionProperties"
                $DirectoryExtensions = New-GraphGetRequest -uri $Uri -AsApp $true -NoAuthCheck $true -tenantid $env:TenantID
                $Existing = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'DirectoryExtension'"

                foreach ($DirectoryExtension in $DirectoryExtensions) {
                    if ($Existing -match $DirectoryExtension.name) {
                        continue
                    }
                    $Entity = @{
                        PartitionKey = 'DirectoryExtension'
                        RowKey       = $DirectoryExtension.name
                        JSON         = [string](ConvertTo-Json $DirectoryExtension -Compress -Depth 5)
                    }
                    Add-CIPPAzDataTableEntity @CustomDataTable -Entity $Entity -Force
                }

                $Body = @{
                    Results = @($DirectoryExtensions)
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to retrieve directory extensions: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'AddDirectoryExtension' {
            try {
                $ExtensionName = $Request.Body.name
                $DataType = $Request.Body.dataType
                $TargetObjects = $Request.Body.targetObjects
                $IsMultiValued = $Request.Body.isMultiValued -eq $true

                if (!$ExtensionName -or !$DataType -or !$TargetObjects) {
                    throw 'Extension name, data type, and target objects are required.'
                }

                $AppId = $env:ApplicationID # Replace with your application ID
                $Uri = "https://graph.microsoft.com/beta/applications(appId='$AppId')/extensionProperties"

                $BodyContent = @{
                    name          = $ExtensionName
                    dataType      = $DataType
                    targetObjects = $TargetObjects
                    isMultiValued = $IsMultiValued
                } | ConvertTo-Json -Depth 5 -Compress

                $Response = New-GraphPOSTRequest -Uri $Uri -Body $BodyContent -AsApp $true -NoAuthCheck $true -tenantid $env:TenantID

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Directory extension '$ExtensionName' added successfully."
                        extension  = $Response
                    }
                }

                # store the extension in the custom data table
                $Entity = @{
                    PartitionKey = 'DirectoryExtension'
                    RowKey       = $Response.name
                    JSON         = [string](ConvertTo-Json $Response -Compress -Depth 5)
                }
                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $Entity -Force
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to add directory extension: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'DeleteDirectoryExtension' {
            try {
                $ExtensionName = $Request.Body.name
                $ExtensionId = $Request.Body.id
                if (!$ExtensionName) {
                    throw 'Extension name is missing in the request body.'
                }
                $AppId = $env:ApplicationID # Replace with your application ID
                $Uri = "https://graph.microsoft.com/beta/applications(appId='$AppId')/extensionProperties/$ExtensionId"

                # Delete the directory extension from Microsoft Graph
                $null = New-GraphPOSTRequest -Type DELETE -Uri $Uri -AsApp $true -NoAuthCheck $true -tenantid $env:TenantID
                try {
                    $CustomDataTable = Get-CippTable -TableName 'CustomData'
                    $ExtensionEntity = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'DirectoryExtension' and RowKey eq '$ExtensionName'"
                    # Remove the extension from the custom data table
                    if ($ExtensionEntity) {
                        Remove-AzDataTableEntity @CustomDataTable -Entity $ExtensionEntity
                    }
                } catch {
                    Write-Warning "Failed to delete directory extension from custom data table: $($_.Exception.Message)"
                }

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = "Directory extension '$ExtensionName' deleted successfully."
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to delete directory extension: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'ListAvailableAttributes' {
            $TargetObject = $Request.Query.targetObject ?? 'All'
            $AvailableAttributes = Get-CippCustomDataAttributes -TargetObject $TargetObject
            $Body = @{
                Results = @($AvailableAttributes)
            }
        }
        'ListMappings' {
            try {
                $Mappings = Get-CIPPAzDataTableEntity @CustomDataMappingsTable | ForEach-Object {
                    $Mapping = $_.JSON | ConvertFrom-Json -AsHashtable

                    Write-Information ($Mapping | ConvertTo-Json -Depth 5)
                    [PSCustomObject]@{
                        id                  = $_.RowKey
                        tenant              = $Mapping.tenantFilter.label
                        dataset             = $Mapping.extensionSyncDataset.label ?? 'N/A'
                        sourceType          = $Mapping.sourceType.label
                        directoryObject     = $Mapping.directoryObjectType.label
                        syncProperty        = $Mapping.extensionSyncProperty.label ?? ($Mapping.extensionSyncDataset ? @($Mapping.extensionSyncDataset.addedFields.select -split ',') : 'N/A')
                        customDataAttribute = $Mapping.customDataAttribute.label
                    }
                }
                $Body = @{
                    Results = @($Mappings)
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to retrieve mappings: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'AddEditMapping' {
            try {
                $Mapping = $Request.Body.Mapping
                if (!$Mapping) {
                    throw 'Mapping data is missing in the request body.'
                }
                $MappingId = $Request.Body.id ?? [Guid]::NewGuid().ToString()
                $Entity = @{
                    PartitionKey = 'Mapping'
                    RowKey       = [string]$MappingId
                    JSON         = [string]($Mapping | ConvertTo-Json -Depth 5 -Compress)
                }

                Add-CIPPAzDataTableEntity @CustomDataMappingsTable -Entity $Entity -Force
                Register-CIPPExtensionScheduledTasks

                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = 'Mapping saved successfully.'
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to add mapping: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'DeleteMapping' {
            try {
                $MappingId = $Request.Body.id
                if (!$MappingId) {
                    throw 'Mapping ID is missing in the request body.'
                }

                # Retrieve the mapping entity
                $MappingEntity = Get-CIPPAzDataTableEntity @CustomDataMappingsTable -Filter "PartitionKey eq 'Mapping' and RowKey eq '$MappingId'"
                if (!$MappingEntity) {
                    throw "Mapping with ID '$MappingId' not found."
                }

                # Delete the mapping entity
                Remove-AzDataTableEntity @CustomDataMappingsTable -Entity $MappingEntity
                Register-CIPPExtensionScheduledTasks
                $Body = @{
                    Results = @{
                        state      = 'success'
                        resultText = 'Mapping deleted successfully.'
                    }
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to delete mapping: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }
        'GetMapping' {
            try {
                $MappingId = $Request.Query.id
                if (!$MappingId) {
                    throw 'Mapping ID is missing in the request query.'
                }

                # Retrieve the mapping entity
                $MappingEntity = Get-CIPPAzDataTableEntity @CustomDataMappingsTable -Filter "PartitionKey eq 'Mapping' and RowKey eq '$MappingId'"
                if (!$MappingEntity) {
                    throw "Mapping with ID '$MappingId' not found."
                }

                $Mapping = $MappingEntity.JSON | ConvertFrom-Json
                $Body = @{
                    Results = $Mapping
                }
            } catch {
                $Body = @{
                    Results = @(
                        @{
                            state      = 'error'
                            resultText = "Failed to retrieve mapping: $($_.Exception.Message)"
                        }
                    )
                }
            }
        }

        default {
            $Body = @{
                Results = @(
                    @{
                        state      = 'error'
                        resultText = 'Invalid action specified.'
                    }
                )
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
