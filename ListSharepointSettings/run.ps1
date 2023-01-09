using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$body = '{"deletedUserPersonalSiteRetentionPeriodInDays": 80}'
$GraphRequest = New-GraphPostRequest -tenantid $tenantfilter -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type PATCH -Body $body -ContentType "application/json"

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
