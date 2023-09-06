using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
Try {
    $GroupStatus = Set-CIPPGroupGAL -Id $Request.query.id -tenantFilter $Request.query.TenantFilter -GroupType $Request.query.groupType -HiddenString $Request.query.HidefromGAL  -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'    
    $Results = [pscustomobject]@{"Results" = $GroupStatus }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Hide/UnHide from GAL failed: $($_.Exception.Message)" -Sev "Error"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
