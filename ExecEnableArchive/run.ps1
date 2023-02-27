using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $tenantfilter = $Request.Query.TenantFilter 
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Enable-Mailbox" -cmdParams @{Identity = $request.query.id; Archive = $true }

    $Results = [pscustomobject]@{"Results" = "Successfully completed task." }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Added archive to $($request.query.id)" -Sev "Info"
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to add archive $($_.Exception.Message)" -Sev "Error"
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
