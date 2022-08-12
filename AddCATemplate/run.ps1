using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host ($request | ConvertTo-Json -Compress)

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
    $JSON = ($JSON | ConvertTo-Json -Depth 10)
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
