using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$tenantDisplayName = $request.body.displayName
$tenantDefaultDomainName = $request.body.defaultDomainName
$Tenant = $request.body.tenantid
$tenantObjID = $request.body.id

$results = try {
    $AADGraphtoken = (Get-GraphToken -scope 'https://graph.windows.net/.default')
    $bodyToPatch = '{"displayName":"' + $tenantDisplayName + '","defaultDomainName":"' + $tenantDefaultDomainName + '"}'
    #$GetContracts = (Invoke-RestMethod -Method GET -Uri 'https://graph.windows.net/myorganization/contracts?api-version=1.6' -ContentType 'application/json' -Headers $AADGraphtoken)
    $PostContracts = (Invoke-RestMethod -Method PATCH -Uri "https://graph.windows.net/myorganization/contracts/$($TenantObjID)?api-version=1.6" -Body $bodyToPatch -ContentType 'application/json' -Headers $AADGraphtoken)
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Edited tenant $($Tenant)" -Sev 'Info'
    Remove-CIPPCache

    "Successfully amended details for $($Tenant) and cleared tenant cache"

}
catch {
    "Failed to amend details for $($Tenant): $($_.ExceptionMessage) <br>"
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed amending details $($tenantDisplayName). Error: $($_.Exception.Message)" -Sev 'Error'
    continue
}


$body = [pscustomobject]@{'Results' = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $body
    })
