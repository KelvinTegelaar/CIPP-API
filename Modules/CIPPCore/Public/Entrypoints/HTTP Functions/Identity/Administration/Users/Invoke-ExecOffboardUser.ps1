using namespace System.Net

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
    $Results = foreach ($username in $AllUsers) {
        try {
            $APIName = 'ExecOffboardUser'
            $Headers = $Request.Headers
            Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

            if ($Request.Body.Scheduled.enabled) {
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
                    ScheduledTime = $Request.Body.Scheduled.date
                    PostExecution = @{
                        Webhook = [bool]$Request.Body.PostExecution.webhook
                        Email   = [bool]$Request.Body.PostExecution.email
                        PSA     = [bool]$Request.Body.PostExecution.psa
                    }
                }
                Add-CIPPScheduledTask -Task $taskObject -hidden $false -Headers $Headers
            } else {
                Invoke-CIPPOffboardingJob -Username $Username -TenantFilter $TenantFilter -Options $OffboardingOptions -APIName $APIName -Headers $Headers
            }
            $StatusCode = [HttpStatusCode]::OK

        } catch {
            $StatusCode = [HttpStatusCode]::Forbidden
            $_.Exception.message
        }
    }
    $body = [pscustomobject]@{'Results' = @($Results) }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
