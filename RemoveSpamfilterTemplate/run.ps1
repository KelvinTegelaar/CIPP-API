using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$ID = $request.query.id
try {
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SpamfilterTemplate' and RowKey eq '$id'" 
    $ClearRow = Get-AzDataTableEntity @Table -Filter $Filter
    Remove-AzDataTableEntity @Table -Entity $clearRow
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME  -message "Removed Transport Rule Template with ID $ID." -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Successfully removed Transport Rule Template" }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME  -message "Failed to remove Transport Rule template $ID. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to remove template: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

