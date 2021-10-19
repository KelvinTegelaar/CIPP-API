using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"$selectlist = "id","accountEnabled","businessPhones","city","createdDateTime","companyName","country","department","displayName","faxNumber","givenName","isResourceAccount","jobTitle","mail","mailNickname","mobilePhone","onPremisesDistinguishedName","officeLocation","onPremisesLastSyncDateTime",@{ Name = 'onPremisesSyncEnabled'; Expression = { if([string]::IsNullOrEmpty($_.onPremisesSyncEnabled)){"false"}else{$_.onPremisesSyncEnabled} } },"otherMails","postalCode","preferredDataLocation","preferredLanguage","proxyAddresses","showInAddressList","state","streetAddress","surname","usageLocation","userPrincipalName","userType","assignedLicenses",@{ Name = 'LicJoined'; Expression = { ($_.assignedLicenses | foreach-object { convert-skuname -skuID $_.skuid }) -join ", " } }, @{ Name = 'Aliasses'; Expression = { $_.Proxyaddresses -join ", " } },@{ Name = 'primDomain'; Expression = { $_.userPrincipalName -split "@" | Select-Object -last 1 } }

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$userid = $Request.Query.UserID
$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$top=999" -tenantid $TenantFilter | select-object $selectList 


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })