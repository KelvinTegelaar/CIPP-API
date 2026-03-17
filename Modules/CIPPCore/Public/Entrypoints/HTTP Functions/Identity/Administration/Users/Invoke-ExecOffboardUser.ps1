function Invoke-ExecOffboardUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $AllUsers = $Request.Body.user.value
    $TenantFilter = $request.Body.tenantFilter.value ? $request.Body.tenantFilter.value : $request.Body.tenantFilter
    $OffboardingOptions = $Request.Body | Select-Object * -ExcludeProperty user, tenantFilter, Scheduled

    $StatusCode = [HttpStatusCode]::OK
    $Results = foreach ($username in $AllUsers) {
        try {
            $Headers = $Request.Headers
            $taskObject = [PSCustomObject]@{
                TenantFilter  = $TenantFilter
                Name          = "Offboarding: $Username"
                Command       = @{
                    value = 'Invoke-CIPPOffboardingJob'
                }
                Parameters    = [pscustomobject]@{
                    Username     = $Username
                    APIName      = 'Scheduled Offboarding'
                    options      = $OffboardingOptions
                    RunScheduled = $true
                }
                PostExecution = @{
                    Webhook = [bool]$Request.Body.PostExecution.webhook
                    Email   = [bool]$Request.Body.PostExecution.email
                    PSA     = [bool]$Request.Body.PostExecution.psa
                }
                Reference     = $Request.Body.reference
            }
            $Params = @{
                Task    = $taskObject
                hidden  = $false
                Headers = $Headers
            }
            if ($Request.Body.Scheduled.enabled) {
                $taskObject.ScheduledTime = $Request.Body.Scheduled.date
            } else {
                $Params.RunNow = $true
            }
            Add-CIPPScheduledTask @Params
        } catch {
            $StatusCode = [HttpStatusCode]::Forbidden
            $_.Exception.message
        }
    }
    $body = [pscustomobject]@{'Results' = @($Results) }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
