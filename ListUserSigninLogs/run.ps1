using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$UserID = $Request.Query.UserID

$StartTime = Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'
$EndDate = (Get-Date).addDays(-1)
$EndTime = Get-Date (Get-Date($EndDate)).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'


$URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$UserID')&`$top=50&`$orderby=createdDateTime desc"
Write-Host $URI
$GraphRequest = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -verbose

#$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D7')" -tenantid $TenantFilter | convertfrom-csv | select-object @{ Name = 'UPN'; Expression = { $_.'Owner Principal Name' } },
#@{ Name = 'displayName'; Expression = { $_.'Owner Display Name' } },
#@{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
#@{ Name = 'FileCount'; Expression = { $_.'File Count' } },
#@{ Name = 'UsedGB'; Expression = { [math]::round($_.'Storage Used (Byte)' /1GB,0) } },
#@{ Name = 'URL'; Expression = { $_.'Site URL' } },
#@{ Name = 'Allocated'; Expression = { $_.'Storage Allocated (Byte)' /1GB } }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })