using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    $Results = if ($Request.body.Scheduled) {
        #Add scheduled task with all params. 
        "Offboarding scheduled for $($Request.body.Scheduled.Date)"
    }
    else {
        Invoke-CIPPOffboardingJob -Username $Username -TenantFilter $Tenantfilter -Options $Request.body -APIName $APIName -ExecutingUser $request.headers.'x-ms-client-principal'
    }
    $StatusCode = [HttpStatusCode]::OK
    $body = [pscustomobject]@{"Results" = @($results) }
}
catch {
    $StatusCode = [HttpStatusCode]::Forbidden
    $body = $_.Exception.message
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }) 
