using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$selectlist = "id", "companyName","department","displayName","proxyAddresses","givenName","jobTitle","mail","mailNickname","onPremisesLastSyncDateTime","onPremisesSyncEnabled","surname","phones","addresses", "Aliasses"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter

Write-Host "Tenant Filter: $TenantFilter"

$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contacts/?`$top=999&`$select=$($selectlist -join ',')" -tenantid $TenantFilter | ForEach-Object {
    $_.onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
    $_.Aliasses = $_.Proxyaddresses -join ", "
    $_
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })

#@{ Name = 'LicJoined'; Expression = { ($_.assignedLicenses | ForEach-Object { convert-skuname -skuID $_.skuid }) -join ", " } }, @{ Name = 'Aliasses'; Expression = { $_.Proxyaddresses -join ", " } }, @{ Name = 'primDomain'; Expression = { $_.userPrincipalName -split "@" | Select-Object -Last 1 } }