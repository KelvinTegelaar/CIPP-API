using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $MobileResults = Set-CIPPMobileDevice -UserId $request.query.Userid -DeviceId $request.query.deviceid -Quarantine $request.query.Quarantine -tenantFilter $request.query.tenantfilter -APIName $APINAME -Delete $Request.query.Delete -ExecutingUser $request.headers.'x-ms-client-principal'
    $Results = [pscustomobject]@{"Results" = $MobileResults }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed  $($request.query.Userid): $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
