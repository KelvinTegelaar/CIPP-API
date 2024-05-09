function Set-CIPPSchemaExtension {
    [CmdletBinding()]
    Param()

    $Schema = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/schemaExtensions?`$filter=owner eq '$($env:applicationid)'" -NoAuthCheck $true -AsApp $true

    $Properties = [PSCustomObject]@(
        @{
            name = 'jitAdminEnabled'
            type = 'Boolean'
        }
        @{
            name = 'jitAdminExpiration'
            type = 'DateTime'
        }
    )
    $TargetTypes = @('User')

    if (!$Schema.id) {
        $Body = [PSCustomObject]@{
            id          = 'cippSchema'
            description = 'CIPP Schema Extension'
            targetTypes = $TargetTypes
            properties  = $Properties
        }

        $Json = ConvertTo-Json -Depth 5 -InputObject $Body
        Write-Host $Json
        $Schema = New-GraphPOSTRequest -type POST -Uri 'https://graph.microsoft.com/v1.0/schemaExtensions' -Body $Json -AsApp $true -NoAuthCheck $true
        $Schema.status = 'Available'
        New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $Json -AsApp $true -NoAuthCheck $true
    } else {
        $Schema = $Schema | Where-Object { $_.id -match 'cippSchema' }
        $Patch = @{}
        if (Compare-Object -ReferenceObject ($Properties | Select-Object name, type) -DifferenceObject $Schema.properties) {
            $Patch.properties = $Properties
        }
        if ($Schema.status -ne 'Available') {
            $Patch.status = 'Available'
        }
        if ($Schema.targetTypes -ne $TargetTypes) {
            $Patch.targetTypes = $TargetTypes
        }

        if ($Patch.Keys.Count -gt 0) {
            $Json = ConvertTo-Json -Depth 5 -InputObject $Patch
            New-GraphPOSTRequest -type PATCH -Uri "https://graph.microsoft.com/v1.0/schemaExtensions/$($Schema.id)" -Body $Json -AsApp $true -NoAuthCheck $true
        } else {
            $Schema
        }
    }
}