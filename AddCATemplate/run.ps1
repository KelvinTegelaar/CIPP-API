using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$TenantFilter = $Request.Query.TenantFilter
try {        
    $GUID = (New-Guid).GUID
    $JSON = if ($request.body.rawjson) {
       ([pscustomobject]$request.body.rawjson) | ConvertFrom-Json
    }
    else {
        ([pscustomobject]$Request.body) | ForEach-Object {
            $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties 
        }
    }
  
    $includelocations = New-Object System.Collections.ArrayList
    $IncludeJSON = foreach ($Location in  $JSON.conditions.locations.includeLocations) {
        $locationinfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $includelocations.add($locationinfo.displayName) } else { $includelocations.add($location) }
        $locationinfo
    }
    if ($includelocations) { $JSON.conditions.locations.includeLocations = $includelocations }


    $excludelocations = New-Object System.Collections.ArrayList
    $ExcludeJSON = foreach ($Location in $JSON.conditions.locations.excludeLocations) {
        $locationinfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $excludelocations.add($locationinfo.displayName) } else { $excludelocations.add($location) }
        $locationinfo
    }

    if ($excludelocations) { $JSON.conditions.locations.excludeLocations = $excludelocations }

    $JSON | Add-Member -NotePropertyName 'LocationInfo' -NotePropertyValue @($IncludeJSON, $ExcludeJSON)

    $JSON = ($JSON | ConvertTo-Json -Depth 100)
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = "CATemplate"
        GUID         = "$GUID"
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created Transport Rule Template $($Request.body.name) with GUID $GUID" -Sev "Debug"
    $body = [pscustomobject]@{"Results" = "Successfully added template" }
    
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Failed to create Transport Rule Template: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Intune Template Deployment failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
