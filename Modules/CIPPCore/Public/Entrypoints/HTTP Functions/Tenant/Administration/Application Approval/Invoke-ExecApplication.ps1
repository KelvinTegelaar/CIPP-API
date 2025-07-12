function Invoke-ExecApplication {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $ValidTypes = @('applications', 'servicePrincipals')
    $ValidActions = @('Update', 'Upsert', 'Delete', 'RemoveKey', 'RemovePassword')

    $Id = $Request.Query.Id ?? $Request.Body.Id
    $Type = $Request.Query.Type ?? $Request.Body.Type
    if (-not $Id) {
        $AppId = $Request.Query.AppId ?? $Request.Body.AppId
        if (-not $AppId) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = "Required parameter 'Id' or 'AppId' is missing"
                })
            return
        }
        $IdPath = "(appId='$AppId')"
    } else {
        $IdPath = "/$Id"
    }
    if ($Type -and $ValidTypes -notcontains $Type) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid Type specified. Valid types are: $($ValidTypes -join ', ')"
            })
        return
    }

    $Uri = "https://graph.microsoft.com/beta/$($Type)$($IdPath)"
    $Action = $Request.Query.Action ?? $Request.Body.Action

    if ($ValidActions -notcontains $Action) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid Action specified. Valid actions are: $($ValidActions -join ', ')"
            })
        return
    }

    $PostParams = @{
        Uri = $Uri
    }

    if ($Action -eq 'Delete') {
        $PostParams.Type = 'DELETE'
    }
    if ($Action -eq 'Update' -or $Action -eq 'Upsert') {
        $PostParams.Type = 'PATCH'
    }

    if ($Action -eq 'Upsert') {
        $PostParams.AddedHeaders = @{
            'Prefer' = 'create-if-missing'
        }
    }

    if ($Request.Body) {
        $PostParams.Body = $Request.Body.Payload | ConvertTo-Json -Compress
    }

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        if ($Action -eq 'RemoveKey' -or $Action -eq 'RemovePassword') {
            # Handle credential removal by patching the object
            $KeyIds = $Request.Body.KeyIds.value ?? $Request.Body.KeyIds
            if (-not $KeyIds -or $KeyIds.Count -eq 0) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = "KeyIds parameter is required for $Action action"
                    })
                return
            }

            # Get the current application/service principal
            $CurrentObject = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -AsApp $true

            if ($Action -eq 'RemoveKey') {
                # Filter out the key credentials to remove
                $UpdatedKeyCredentials = $CurrentObject.keyCredentials | Where-Object { $_.keyId -notin $KeyIds }
                $PatchBody = @{
                    keyCredentials = @($UpdatedKeyCredentials)
                }
            } else {
                # Filter out the password credentials to remove
                $UpdatedPasswordCredentials = $CurrentObject.passwordCredentials | Where-Object { $_.keyId -notin $KeyIds }
                $PatchBody = @{
                    passwordCredentials = @($UpdatedPasswordCredentials)
                }
            }

            # Update the object with the filtered credentials
            $null = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body ($PatchBody | ConvertTo-Json -Depth 10) -tenantid $TenantFilter -AsApp $true

            $Results = @{
                resultText = "Successfully removed $($KeyIds.Count) credential(s) from $Type"
                state      = 'success'
            }
        } else {
            # Handle regular actions
            $null = New-GraphPOSTRequest @PostParams -tenantid $TenantFilter -AsApp $true
            $Results = @{
                resultText = "Successfully executed $Action on $Type with Id: $Id"
                state      = 'success'
            }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $Results = @{
            resultText = "Failed to execute $Action on $Type with Id: $Id. Error: $($_.Exception.Message)"
            state      = 'error'
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = @($Results) }
            })
    }
}