using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $ResultsArch = Set-CIPPMailboxArchive -userid $Request.query.id -tenantFilter $Request.query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -ArchiveEnabled $true
    $Results = [pscustomobject]@{"Results" = "$ResultsArch" }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
