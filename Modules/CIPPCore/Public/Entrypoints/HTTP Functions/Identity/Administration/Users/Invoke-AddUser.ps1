function Invoke-AddUser {
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

    if (!$UserObj.tenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{
                    'Results' = @{
                        resultText = 'tenantFilter is required to create a user.'
                        state      = 'error'
                    }
                }
            })
    }

    if ($UserObj.Scheduled.Enabled) {
        try {
            $Username = $UserObj.username ?? $UserObj.mailNickname
            $TaskBody = [pscustomobject]@{
                TenantFilter  = $UserObj.tenantFilter
                Name          = "New user creation: $($Username)@$($UserObj.PrimDomain.value)"
                Command       = @{
                    value = 'New-CIPPUserTask'
                    label = 'New-CIPPUserTask'
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
            $body = [pscustomobject] @{
                'Results' = @("Successfully created scheduled task to create user $($UserObj.DisplayName)")
            }
        } catch {
            $body = [pscustomobject] @{
                'Results' = @("Failed to create scheduled task to create user $($UserObj.DisplayName): $($_.Exception.Message)")
            }
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    } else {
        try {
            $CreationResults = New-CIPPUserTask -UserObj $UserObj -APIName $APIName -Headers $Headers
            $body = [pscustomobject] @{
                'Results'  = @(
                    $CreationResults.Results[0],
                    $CreationResults.Results[1],
                    @{
                        'resultText' = $CreationResults.Results[2]
                        'copyField'  = $CreationResults.password
                        'state'      = 'success'
                    }
                )
                'CopyFrom' = @{
                    'Success' = $CreationResults.CopyFrom.Success
                    'Error'   = $CreationResults.CopyFrom.Error
                }
                'User'     = $CreationResults.User
            }
        } catch {
            $ErrorMessage = $_.TargetObject.Results -join ' '
            $ErrorMessage = [string]::IsNullOrWhiteSpace($ErrorMessage) ? $_.Exception.Message : $ErrorMessage
            $body = [pscustomobject] @{
                'Results' = @($ErrorMessage)
            }
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ? $StatusCode : [HttpStatusCode]::OK
            Body       = $Body
        })

}
