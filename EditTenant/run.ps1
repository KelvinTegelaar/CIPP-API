using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.

$tenantDisplayName = $request.body.displayName
$tenantDefaultDomainName = $request.body.defaultDomainName
$Tenant = $request.body.tenantid
$tenantObjID = $request.body.id


$results = try {
    $bodyToPatch = '{"displayName":"' + $tenantDisplayName + '","defaultDomainName":"' + $tenantDefaultDomainName + '",}'
    $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/contracts/$tenantObjID" -type PATCH -body $bodyToPatch
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Edited tenant $($Tenant)" -Sev "Info"
    Remove-CIPPCache

    "Successfully amended details for $($Tenant) and cleared tenant cache<br>"

} catch {
    "Failed to amend details for $($Tenant): $($_.ExceptionMessage) <br>"
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed amending details $($tenantDisplayName). Error: $($_.Exception.Message)" -Sev "Error"
    continue
}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
