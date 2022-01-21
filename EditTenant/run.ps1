using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$tenantDisplayName = $request.body.displayName
$tenantDefaultDomainName = $request.body.defaultDomainName
$Tenant = $request.body.tenantid
$customerContextId = $request.body.customerId

$tokens = try {

    $AADGraphtoken = (Get-GraphToken -scope 'https://graph.windows.net/.default')
    $allTenantsDetails = (Invoke-RestMethod -Method GET -Uri 'https://graph.windows.net/myorganization/contracts?api-version=1.6' -ContentType 'application/json' -Headers $AADGraphtoken)
    $tenantObjectId = $allTenantsDetails.value | Where-Object { $_.customerContextId -eq $customerContextId } | Select-Object 'objectId'
} catch {
    "Failed to retrieve list of tenants.  Error: $($_.ExceptionMessage)"
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantDisplayName) -message "Failed to retrieve list of tenants. Error: $($_.Exception.Message)" -Sev 'Error'
}


$results = if ($tenantObjectId) {
    try {
        $bodyToPatch = '{"displayName":"' + $tenantDisplayName + '","defaultDomainName":"' + $tenantDefaultDomainName + '"}'
        $patchTenant = (Invoke-RestMethod -Method PATCH -Uri "https://graph.windows.net/myorganization/contracts/$($tenantObjectId.objectId)?api-version=1.6" -Body $bodyToPatch -ContentType 'application/json' -Headers $AADGraphtoken)    
        
        if (Test-Path -Path '.\tenants.cache.json') {
            try {
                Remove-CIPPCache
            }
            catch { 
                'There was an error removing the tenants cache for some reason.' 
            } 
        }
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Edited tenant $($Tenant)" -Sev 'Info'
        "Successfully amended details for $($Tenant) and cleared tenant cache"
    }
    catch { 
        "Failed to amend details for $($Tenant): $($_.ExceptionMessage)"
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed amending details $($Tenant). Error: $($_.Exception.Message)" -Sev 'Error'
        continue
    }
}

$body = [pscustomobject]@{'Results' = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
