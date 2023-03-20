using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$tenantfilter = $Request.Query.TenantFilter
$DeviceFilter = $Request.Query.GUID
$Action = $Request.Query.Action
if ($Action -eq "setDeviceName") {
    $ActionBody = @{ deviceName = $Request.Body.input } | convertto-json -compress
} else {
$ActionBody = if ($Request.body) { $Request.body | ConvertTo-Json } else { '{}' }
}
try {     
    $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)" -type POST -tenantid $TenantFilter -body $actionbody 
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Queued $Action on $DeviceFilter" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Queued $Action on $DeviceFilter" }

}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to queue action $action on $DeviceFilter : $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to queue action $action on $DeviceFilter $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
