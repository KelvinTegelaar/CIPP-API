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
    $params = @{
        Identity     = $request.query.ID; 
        AllowSender  = [boolean]$Request.query.AllowSender
        ReleasetoAll = [boolean]$Request.query.type
        ActionType   = $Request.query.type
    }
    Write-Host $params
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Release-QuarantineMessage" -cmdParams $Params
    $Results = [pscustomobject]@{"Results" = "Successfully processed $($request.query.ID)" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id)" -Sev "Info"
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Quarantine Management failed: $($_.Exception.Message)" -Sev "Error"
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
