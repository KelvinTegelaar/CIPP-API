using namespace System.Net

Function Invoke-ExecOffboardUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $AllUsers = $Request.body.user.value
    $Tenantfilter = $request.body.tenantfilter.value
    $Results = foreach ($username in $AllUsers) {
        try {
            $APIName = 'ExecOffboardUser'
            Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

            if ($Request.body.Scheduled.enabled) {
                $taskObject = [PSCustomObject]@{
                    TenantFilter  = $Tenantfilter
                    Name          = "Offboarding: $Username"
                    Command       = @{
                        value = 'Invoke-CIPPOffboardingJob'
                    }
                    Parameters    = [pscustomobject]@{
                        Username     = $Username
                        APIName      = 'Scheduled Offboarding'
                        options      = $request.body
                        RunScheduled = $true
                    }
                    ScheduledTime = $Request.body.scheduled.date
                    PostExecution = @{
                        Webhook = [bool]$Request.Body.PostExecution.webhook
                        Email   = [bool]$Request.Body.PostExecution.email
                        PSA     = [bool]$Request.Body.PostExecution.psa
                    }
                }
                Add-CIPPScheduledTask -Task $taskObject -hidden $false -Headers $Request.Headers
            } else {
                Invoke-CIPPOffboardingJob -Username $Username -TenantFilter $Tenantfilter -Options $Request.body -APIName $APIName -Headers $Request.Headers
            }
            $StatusCode = [HttpStatusCode]::OK

        } catch {
            $StatusCode = [HttpStatusCode]::Forbidden
            $body = $_.Exception.message
        }
    }
    $body = [pscustomobject]@{'Results' = @($results) }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
