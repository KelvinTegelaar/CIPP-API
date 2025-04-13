function Get-CIPPSchemaExtensions {
    [CmdletBinding()]
    Param(
        [switch]$Update,
        $Headers
    )

    # Get definitions file
    $CIPPCore = Get-Module -Name 'CIPPCore' | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item -Path $CIPPCore).Parent.Parent
    $SchemaDefinitionsPath = Join-Path $CIPPRoot 'Config\schemaDefinitions.json'

    # check CustomData table for schema extensions
    $CustomDataTable = Get-CippTable -tablename 'CustomData'
    try {
        $SchemaExtensions = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'"
    } catch {
        $SchemaExtensions = @()
    }

    $SchemaDefinitions = Get-Content -Path $SchemaDefinitionsPath | ConvertFrom-Json
    $SchemaDefinitions | ForEach-Object {
        if ($SchemaExtensions -notcontains $_.id -or $Update.IsPresent) {
            Write-Information "Adding Schema Extension for $($_.id) to table"
            $Schema = @{
                PartitionKey = 'SchemaExtension'
                RowKey       = [string]$_.id
                JSON         = [string]($_ | ConvertTo-Json -Depth 5 -Compress)
            }
            Add-CIPPAzDataTableEntity @CustomDataTable -Entity $Schema -Force
        }
    }
    if (!$SchemaExtensions) {
        $SchemaExtensions = Get-CIPPAzDataTableEntity @CustomDataTable -Filter "PartitionKey eq 'SchemaExtension'"
    }

    $Schemas = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/schemaExtensions?`$filter=owner eq '$($env:ApplicationID)'" -NoAuthCheck $true -AsApp $true | Where-Object { $_.status -ne 'Deprecated' }

    foreach ($SchemaExtension in $SchemaExtensions) {
        $SchemaFound = $false
        $SchemaDefinition = $SchemaExtension.JSON | ConvertFrom-Json
        Write-Information "Processing Schema Extension for $($SchemaDefinition.id)"
        foreach ($Schema in $Schemas) {
            if ($Schema.id -match $SchemaDefinition.id) {
                Write-Verbose ($Schema | ConvertTo-Json -Depth 5)
                $Patch = @{}
                $SchemaFound = $true
                $Schema = $Schemas | Where-Object { $_.id -match $SchemaDefinition.id } | Select-Object -First 1
                if (Compare-Object -ReferenceObject ($SchemaDefinition.properties | Sort-Object name | Select-Object name, type) -DifferenceObject ($Schema.properties | Sort-Object name | Select-Object name, type)) {
                    $Patch.properties = $SchemaDefinition.properties
                }
                if ($Schema.status -ne $SchemaDefinition.status) {
                    $Patch.status = $SchemaDefinition.status
                }
                if ($Schema.targetTypes -ne $SchemaDefinition.targetTypes) {
                    $Patch.targetTypes = $SchemaDefinition.targetTypes
                }
                if ($Patch -and $Patch.Keys.Count -gt 0) {
                    Write-Information "Updating $($Schema.id)"
                    $Json = ConvertTo-Json -Depth 5 -InputObject $Patch
                    Write-Verbose $Json
                    $null = New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $Json -AsApp $true -NoAuthCheck $true
                    $Schema = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -AsApp $true -NoAuthCheck $true
                    Write-LogMessage -headers $Headers -message "Updated Schema Extension: $($SchemaDefinition.id)" -API 'Get-CIPPSchemaExtensions' -Sev 'info' -LogData $Body
                }
                if ($Patch.status -eq 'Deprecated') {
                    Remove-AzDataTableEntity @CustomDataTable -Entity $SchemaExtension -Force
                } else {
                    $NewSchema = [string]($Schema | ConvertTo-Json -Depth 5 -Compress)
                    if ($SchemaExtension.JSON -ne $NewSchema) {
                        $SchemaExtension.JSON = $NewSchema
                        Add-CIPPAzDataTableEntity @CustomDataTable -Entity $SchemaExtension -Force
                    }
                }
                $Schema
            }
        }
        if (!$SchemaFound) {
            Write-Information "Creating Schema Extension for $($SchemaDefinition.id)"
            $Json = ConvertTo-Json -Depth 5 -InputObject ($SchemaDefinition | Select-Object -ExcludeProperty status)
            $Schema = New-GraphPOSTRequest -type POST -Uri 'https://graph.microsoft.com/v1.0/schemaExtensions' -Body $Json -AsApp $true -NoAuthCheck $true

            if ($SchemaDefinition.status -ne 'InDevelopment') {
                $Patch = [PSCustomObject]@{
                    status = $SchemaDefinition.status
                }
                $PatchJson = ConvertTo-Json -Depth 5 -InputObject $Patch
                $null = New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $PatchJson -AsApp $true -NoAuthCheck $true
            }
            try {
                $OldSchema = $SchemaExtensions | Where-Object { $Schema.id -match $_.RowKey }
                $OldSchema.JSON = [string]($Schema | ConvertTo-Json -Depth 5 -Compress)
                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $OldSchema -Force
            } catch {
                Write-Warning 'Failed to update schema extension in table'
                Write-Warning ($OldSchema | ConvertTo-Json -Depth 5)
            }
            Write-LogMessage -headers $Headers -message "Created Schema Extension: $($SchemaDefinition.id)" -API 'Get-CIPPSchemaExtensions' -Sev 'info' -LogData $Body
            $Schema
        }
    }
    if ($Schemas) {
        $Schemas | ForEach-Object {
            $SchemaFound = $false
            foreach ($SchemaExtension in $SchemaExtensions) {
                $SchemaDefinition = $SchemaExtension.JSON | ConvertFrom-Json
                if ($SchemaDefinition.id -match $_.id) {
                    $SchemaFound = $true
                }
            }
            if (!$SchemaFound) {
                $Json = ConvertTo-Json -Depth 5 -InputObject $_
                $SchemaEntity = @{
                    PartitionKey = 'SchemaExtension'
                    RowKey       = [string]($_.id -split '_' | Select-Object -Last 1)
                    JSON         = [string]$Json
                }
                Add-CIPPAzDataTableEntity @CustomDataTable -Entity $SchemaEntity -Force
                $_
            }
        }
    }
}
