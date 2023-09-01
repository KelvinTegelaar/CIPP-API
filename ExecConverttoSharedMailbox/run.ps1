using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $MailboxType = if ($request.query.ConvertToUser -eq 'true') { "Regular" } else { "Shared" }
    $ConvertedMailbox = Set-CIPPMailboxType -userid $Request.query.id -tenantFilter $Request.query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -MailboxType $MailboxType
    $Results = [pscustomobject]@{"Results" = "$ConvertedMailbox" }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed to convert $($request.query.id) - $($_.Exception.Message)" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
