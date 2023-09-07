using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

Try {
    $MessageResult = New-CIPPOneDriveShortCut -userid $Request.query.id -TenantFilter $Request.query.TenantFilter -URL $Request.query.URL -ExecutingUser $request.headers.'x-ms-client-principal'
    $Results = [pscustomobject]@{ "Results" = "$MessageResult" }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Onedrive Shortcut creation failed: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
