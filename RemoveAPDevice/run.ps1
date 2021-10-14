using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$Deviceid = $Request.Query.ID

try{
if ($TenantFilter -eq $null -or $TenantFilter -eq "null") {
    $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -type DELETE
}
else {
    $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/$Deviceid" -tenantid $TenantFilter -type DELETE
}
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Deleted autopilot device $Deviceid for tenant $TenantFilter" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Succesfully deleted the autopilot device" }
} catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Autopilot Delete API failed for $deviceid - $tenantid. The error is: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to delete device: $($_.Exception.Message)" }
}
#force a sync, this can give "too many requests" if deleleting a bunch of devices though.
    $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync" -tenantid $TenantFilter -type POST -body "{}"

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })