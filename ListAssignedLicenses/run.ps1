using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$selectlist = "id", "accountEnabled", "displayName", "isResourceAccount", "mail", "userPrincipalName", "userType", "assignedLicenses", "onPremisesSyncEnabled", "LicJoined"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$ConvertTable = Import-Csv Conversiontable.csv | Sort-Object -Property 'guid' -Unique
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=assignedLicenses/`$count ne 0&`$count=true &`$select=$($selectlist -join ',')" -tenantid $TenantFilter -ComplexFilter | Select-Object $selectlist | ForEach-Object {
    $_.onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
    $_.Aliases = $_.Proxyaddresses -join ", "
    $SkuID = $_.AssignedLicenses.skuid
    $_.LicJoined = ($ConvertTable | Where-Object { $_.guid -in $skuid }).'Product_Display_Name' -join ", "
    $_
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })