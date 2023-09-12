using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

try {        
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    $guid = $request.body.guid
    $JSON = $request.body | Select-Object * -ExcludeProperty GUID | ConvertTo-Json
    $Type = $request.Query.Type
    Add-AzDataTableEntity @Table -Entity @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = "$Type"
        GUID         = "$GUID"
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Edited template $($Request.body.name) with GUID $GUID" -Sev "Debug"
    $body = [pscustomobject]@{ "Results" = "Successfully saved the template" }
    
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Failed to edit template: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Editing template failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
