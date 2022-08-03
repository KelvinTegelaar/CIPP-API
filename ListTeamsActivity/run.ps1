using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$type = $request.query.Type
$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
@{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
@{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
@{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
@{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })