using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$tenantfilter = $Request.Query.TenantFilter
$appFilter = $Request.Query.AppFilter
write-host "Using $appFilter"
$body = @"
{"select":["DeviceName","UserPrincipalName","Platform","AppVersion","InstallState","InstallStateDetail","LastModifiedDateTime","DeviceId","ErrorCode","UserName","UserId","ApplicationId","AssignmentFilterIdsList","AppInstallState","AppInstallStateDetails","HexErrorCode"],"skip":0,"top":999,"filter":"(ApplicationId eq '$Appfilter')","orderBy":[]}
"@
    $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceManagement/reports/getDeviceInstallStatusReport" -tenantid $TenantFilter -body $body



# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $GraphRequest
    })
