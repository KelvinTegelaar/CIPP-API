function Invoke-PatchUser {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $HttpResponse = [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{'Results' = @("Default response, you should never see this.") }
    }

    try {
        # Handle array of user objects or single user object
        $Users = if ($Request.Body -is [array]) {
            $Request.Body
        } else {
            @($Request.Body)
        }

        # Validate that all users have required properties
        $InvalidUsers = $Users | Where-Object {
            [string]::IsNullOrWhiteSpace($_.id) -or [string]::IsNullOrWhiteSpace($_.tenantFilter)
        }
        if ($InvalidUsers.Count -gt 0) {
            $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
            $HttpResponse.Body = @{'Results' = @('Failed to patch user(s). Some users are missing id or tenantFilter') }
        } else {
            # Group users by tenant filter
            $UsersByTenant = $Users | Group-Object -Property tenantFilter

            $TotalSuccessCount = 0
            $AllErrorMessages = @()

            # Process each tenant separately
            foreach ($TenantGroup in $UsersByTenant) {
                $tenantFilter = $TenantGroup.Name
                $TenantUsers = $TenantGroup.Group

                # Build bulk requests for this tenant
                $int = 0
                $BulkRequests = foreach ($User in $TenantUsers) {
                    # Remove the id and tenantFilter properties from the body since they're not user properties
                    $PatchBody = $User | Select-Object -Property * -ExcludeProperty id, tenantFilter

                    @{
                        id        = $int++
                        method    = 'PATCH'
                        url       = "users/$($User.id)"
                        body      = $PatchBody
                        'headers' = @{
                            'Content-Type' = 'application/json'
                        }
                    }
                }

                # Execute bulk request for this tenant
                $BulkResults = New-GraphBulkRequest -tenantid $tenantFilter -Requests @($BulkRequests)

                # Process results for this tenant
                for ($i = 0; $i -lt $BulkResults.Count; $i++) {
                    $result = $BulkResults[$i]
                    $user = $TenantUsers[$i]

                    if ($result.status -eq 200 -or $result.status -eq 204) {
                        $TotalSuccessCount++
                        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantFilter -message "Successfully patched user $($user.id)" -Sev 'Info'
                    } else {
                        $errorMsg = if ($result.body.error.message) {
                            $result.body.error.message
                        } else {
                            "Unknown error (Status: $($result.status))"
                        }
                        $AllErrorMessages += "Failed to patch user $($user.id) in tenant $($tenantFilter): $errorMsg"
                        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantFilter -message "Failed to patch user $($user.id). Error: $errorMsg" -Sev 'Error'
                    }
                }
            }

            # Build final response
            if ($AllErrorMessages.Count -eq 0) {
                $TenantCount = ($Users | Select-Object -Property tenantFilter -Unique).Count
                $HttpResponse.Body = @{'Results' = @("Successfully patched $TotalSuccessCount user$(if($TotalSuccessCount -ne 1){'s'}) across $TenantCount tenant$(if($TenantCount -ne 1){'s'})") }
            } else {
                $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
                $HttpResponse.Body = @{'Results' = $AllErrorMessages + @("Successfully patched $TotalSuccessCount of $($Users.Count) users") }
            }
        }

    } catch {
        $HttpResponse.StatusCode = [HttpStatusCode]::InternalServerError
        $HttpResponse.Body = @{'Results' = @("Failed to patch user(s). Error: $($_.Exception.Message)") }
    }

    Push-OutputBinding -Name Response -Value $HttpResponse
}