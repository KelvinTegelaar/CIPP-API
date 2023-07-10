using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$ID = $request.query.id
try {
    $Table = Get-CippTable -tablename 'standards'
    $Filter = "PartitionKey eq 'standards' and RowKey eq '$id'" 
    $ClearRow = Get-AzDataTableEntity @Table -Filter $Filter
    Remove-AzDataTableEntity @Table -Entity $clearRow
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME  -message "Removed standards for $ID." -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Successfully removed standards deployment" }


}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME  -message "Failed to remove standard for $ID. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to remove standard)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

