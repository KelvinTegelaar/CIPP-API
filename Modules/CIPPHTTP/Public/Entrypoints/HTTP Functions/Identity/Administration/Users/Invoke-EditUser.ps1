function Invoke-EditUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $UserObj = $Request.Body
    if ([string]::IsNullOrWhiteSpace($UserObj.id)) {
        $body = @{'Results' = @('Failed to edit user. No user ID provided') }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
    }

    if ($UserObj.Scheduled.Enabled) {
        try {
            $TaskBody = [pscustomobject]@{
                TenantFilter  = $UserObj.tenantFilter
                Name          = "Edit user: $($UserObj.DisplayName)"
                Command       = @{
                    value = 'Set-CIPPUser'
                    label = 'Set-CIPPUser'
                }
                Parameters    = [pscustomobject]@{ UserObj = $UserObj }
                ScheduledTime = $UserObj.Scheduled.date
                Reference     = $UserObj.reference ?? $null
                PostExecution = @{
                    Webhook = [bool]$Request.Body.PostExecution.Webhook
                    Email   = [bool]$Request.Body.PostExecution.Email
                    PSA     = [bool]$Request.Body.PostExecution.PSA
                }
            }
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false -DisallowDuplicateName $true -Headers $Headers
            $body = [pscustomobject]@{
                'Results' = @("Successfully created scheduled task to edit user $($UserObj.DisplayName)")
            }
        } catch {
            $body = [pscustomobject]@{
                'Results' = @("Failed to create scheduled task to edit user $($UserObj.DisplayName): $($_.Exception.Message)")
            }
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        try {
            $EditResults = Set-CIPPUser -UserObj $UserObj -APIName $APIName -Headers $Headers
            $body = [pscustomobject]@{ 'Results' = @($EditResults.Results) }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $body = [pscustomobject]@{
                'Results' = @("Failed to edit user. $($ErrorMessage.NormalizedError)")
            }
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ? $StatusCode : [HttpStatusCode]::OK
            Body       = $Body
        })

}
