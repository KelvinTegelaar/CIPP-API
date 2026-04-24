function Invoke-ExecApplication {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $ValidTypes = @('applications', 'servicePrincipals')
    $ValidActions = @('Update', 'Upsert', 'Delete', 'RemoveKey', 'RemovePassword')

    $Id = $Request.Query.Id ?? $Request.Body.Id
    $Type = $Request.Query.Type ?? $Request.Body.Type
    if (-not $Id) {
        $AppId = $Request.Query.AppId ?? $Request.Body.AppId
        if (-not $AppId) {
            return ([HttpResponseContext]@{
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
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid Type specified. Valid types are: $($ValidTypes -join ', ')"
            })
        return
    }

    $Uri = "https://graph.microsoft.com/beta/$($Type)$($IdPath)"
    $Action = $Request.Query.Action ?? $Request.Body.Action

    if ($ValidActions -notcontains $Action) {
        return ([HttpResponseContext]@{
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
            # Handle credential removal
            $KeyIds = $Request.Body.KeyIds.value ?? $Request.Body.KeyIds
            if (-not $KeyIds -or $KeyIds.Count -eq 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = "KeyIds parameter is required for $Action action"
                    })
                return
            }

            if ($Action -eq 'RemoveKey') {
                # For key credentials, use a single PATCH request
                $CurrentObject = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -AsApp $true
                $UpdatedKeyCredentials = $CurrentObject.keyCredentials | Where-Object { $_.keyId -notin $KeyIds }
                $PatchBody = @{
                    keyCredentials = @($UpdatedKeyCredentials)
                }

                $Response = New-GraphPOSTRequest -Uri $Uri -Type 'PATCH' -Body ($PatchBody | ConvertTo-Json -Depth 10) -tenantid $TenantFilter -AsApp $true

                $Results = @{
                    resultText = "Successfully removed $($KeyIds.Count) key credential(s) from $Type"
                    state      = 'success'
                    details    = @($Response)
                }
            } else {
                # For password credentials, use bulk removePassword requests
                $BulkRequests = foreach ($KeyId in $KeyIds) {
                    $RemoveBody = @{
                        keyId = $KeyId
                    }

                    @{
                        id      = $KeyId
                        method  = 'POST'
                        url     = "$($Type)$($IdPath)/removePassword"
                        body    = $RemoveBody
                        headers = @{
                            'Content-Type' = 'application/json'
                        }
                    }
                }

                $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter -AsApp $true

                $SuccessCount = ($BulkResults | Where-Object { $_.status -eq 204 }).Count
                $FailureCount = ($BulkResults | Where-Object { $_.status -ne 204 }).Count

                $Results = @{
                    resultText = "Bulk RemovePassword completed. Success: $SuccessCount, Failures: $FailureCount"
                    state      = if ($FailureCount -eq 0) { 'success' } else { 'error' }
                    details    = @($BulkResults)
                }
            }
        } else {
            # Handle regular actions
            $null = New-GraphPOSTRequest @PostParams -tenantid $TenantFilter -AsApp $true
            $Results = @{
                resultText = "Successfully executed $Action on $Type with Id: $Id"
                state      = 'success'
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $Results = @{
            resultText = "Failed to execute $Action on $Type with Id: $Id. Error: $($_.Exception.Message)"
            state      = 'error'
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = @($Results) }
            })
    }
}
