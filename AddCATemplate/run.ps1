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
  
    $IncludeJSON = foreach ($Location in  $JSON.conditions.locations.includeLocations) {
        Write-Host "There is included JSON"
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
    }
    if ($IncludeJSON) { $JSON.conditions.locations.includeLocations = @($IncludeJSON) }

    $ExcludeJSON = foreach ($Location in $JSON.conditions.locations.Excludelocations) {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
    }
    if ($ExcludeJSON) { $JSON.conditions.locations.excludeLocations = @($ExcludeJSON) }

    $JSON = ($JSON | ConvertTo-Json -Depth 100)
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-AzDataTableEntity @Table -Entity @{
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
