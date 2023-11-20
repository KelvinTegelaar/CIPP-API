using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    $Results = if ($Request.body.Scheduled.enabled) {
        $taskObject = [PSCustomObject]@{
            TenantFilter  = $Tenantfilter
            Name          = "Offboarding: $Username"
            Command       = @{
                value = "Invoke-CIPPOffboardingJob"
            }
            Parameters    = @{
                Username = $Username
                APIName  = "Scheduled Offboarding"
                options  = $request.body
            }
            ScheduledTime = $Request.body.scheduled.date
            PostExecution = @{
                Webhook = [bool]$Request.Body.PostExecution.webhook
                Email   = [bool]$Request.Body.PostExecution.email
                PSA     = [bool]$Request.Body.PostExecution.psa
            }
        }

        Add-CIPPScheduledTask -Task $taskObject -hidden $false
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
$Request.Body.PostExecution
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }) 
