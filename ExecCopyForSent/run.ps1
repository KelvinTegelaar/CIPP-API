using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $MessageCopyForSentAsEnabled = if ($request.query.MessageCopyForSentAsEnabled -eq 'false') { "false" } else { "true" }
    $tenantfilter = $Request.Query.TenantFilter 
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $request.query.id; MessageCopyForSentAsEnabled = $MessageCopyForSentAsEnabled }

    $Results = [pscustomobject]@{"Results" = "Successfully set MessageCopyForSentAsEnabled as $MessageCopyForSentAsEnabled on $($request.query.id)." }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Successfully set MessageCopyForSentAsEnabled as $MessageCopyForSentAsEnabled on $($request.query.id)." -Sev "Info"
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "set MessageCopyForSentAsEnabled to $MessageCopyForSentAsEnabled failed: $($_.Exception.Message)" -Sev "Error"
    $Results = [pscustomobject]@{"Results" = "set MessageCopyForSentAsEnabled to $MessageCopyForSentAsEnabled failed - $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
