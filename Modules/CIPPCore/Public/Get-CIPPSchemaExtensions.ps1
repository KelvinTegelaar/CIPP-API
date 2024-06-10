function Get-CIPPSchemaExtensions {
    [CmdletBinding()]
    Param()

    $Schemas = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/schemaExtensions?`$filter=owner eq '$($env:applicationid)' and status eq 'Available'" -NoAuthCheck $true -AsApp $true

    $SchemaDefinitions = [PSCustomObject]@(
        @{
            id          = 'cippUser'
            description = 'CIPP User Schema'
            targetTypes = @('User')
            properties  = @(
                @{
                    name = 'jitAdminEnabled'
                    type = 'Boolean'
                }
                @{
                    name = 'jitAdminExpiration'
                    type = 'DateTime'
                }
                @{
                    name = 'mailboxType'
                    type = 'String'
                }
                @{
                    name = 'archiveEnabled'
                    type = 'Boolean'
                }
                @{
                    name = 'autoExpandingArchiveEnabled'
                    type = 'Boolean'
                }
            )
        }
    )
    foreach ($SchemaDefinition in $SchemaDefinitions) {
        $SchemaFound = $false
        foreach ($Schema in $Schemas) {
            if ($Schema.id -match $SchemaDefinition.id) {
                $SchemaFound = $true
                $Schema = $Schemas | Where-Object { $_.id -match $SchemaDefinition.id }
                $Patch = @{}
                if (Compare-Object -ReferenceObject ($SchemaDefinition.properties | Select-Object name, type) -DifferenceObject $Schema.properties) {
                    $Patch.properties = $Properties
                }
                if ($Schema.status -ne 'Available') {
                    $Patch.status = 'Available'
                }
                if ($Schema.targetTypes -ne $SchemaDefinition.targetTypes) {
                    $Patch.targetTypes = $SchemaDefinition.targetTypes
                }
                if ($Patch.Keys.Count -gt 0) {
                    Write-Information "Updating $($Schema.id)"
                    $Json = ConvertTo-Json -Depth 5 -InputObject $Patch
                    New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $Json -AsApp $true -NoAuthCheck $true
                } else {
                    $Schema
                }
            }
        }
        if (!$SchemaFound) {
            Write-Information "Creating Schema Extension for $($SchemaDefinition.id)"
            $Body = [PSCustomObject]@{
                id          = 'cippUser'
                description = 'CIPP User'
                targetTypes = $SchemaDefinition.TargetTypes
                properties  = $SchemaDefinition.Properties
            }

            $Json = ConvertTo-Json -Depth 5 -InputObject $Body
            $Schema = New-GraphPOSTRequest -type POST -Uri 'https://graph.microsoft.com/v1.0/schemaExtensions' -Body $Json -AsApp $true -NoAuthCheck $true
            $Patch = [PSCustomObject]@{
                status = 'Available'
            }
            $PatchJson = ConvertTo-Json -Depth 5 -InputObject $Patch
            New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $PatchJson -AsApp $true -NoAuthCheck $true
        }
    }
}