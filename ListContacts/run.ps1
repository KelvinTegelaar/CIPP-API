using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$selectlist = "id", "companyName", "displayName", "mail", "onPremisesSyncEnabled", "editURL"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$ContactID = $Request.Query.ContactID

Write-Host "Tenant Filter: $TenantFilter"
try {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contacts/$($ContactID)?`$top=999&`$select=$($selectlist -join ',')" -tenantid $TenantFilter | Select-Object $selectlist | ForEach-Object {
        $_.editURL = "https://outlook.office365.com/ecp/@$TenantFilter/UsersGroups/EditContact.aspx?exsvurl=1&realm=$($env:TenantID)&mkt=en-US&id=$($_.id)"
        $_
    }
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
