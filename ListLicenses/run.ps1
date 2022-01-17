using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if ($TenantFilter) {
    $RawGraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus" -tenantid $TenantFilter
}
else {
    $RawGraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus"
}
$ConvertTable = import-csv Conversiontable.csv

$GraphRequest = foreach ($SingleRequest in $RawGraphRequest) {
   $prettyname = convert-skuname -skuname $($SingleRequest.skuPartNumber)
   if($prettyname){$SingleRequest.skuPartNumber = $PrettyName }
    $SingleRequest | Select-Object id,skuId,skuPartNumber,consumedUnits,@{ Name = 'availableUnits';  Expression = {$_.prepaidUnits.enabled - $_.consumedUnits}}
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })