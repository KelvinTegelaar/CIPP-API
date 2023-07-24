using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $RemoveResults = Remove-CIPPGroup -ID $Request.query.id -GroupType $Request.query.GroupType -tenantFilter $Request.query.TenantFilter -displayName $Request.query.displayName  -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
    $Results = [pscustomobject]@{"Results" = $RemoveResults }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
