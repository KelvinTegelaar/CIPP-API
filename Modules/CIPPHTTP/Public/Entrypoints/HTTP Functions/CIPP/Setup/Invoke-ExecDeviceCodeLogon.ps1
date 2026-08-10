function Invoke-ExecDeviceCodeLogon {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $clientId = $Request.Query.clientId
        $scope = $Request.Query.scope
        $tenantId = $Request.Query.tenantId
        $deviceCode = $Request.Query.deviceCode

        if (!$scope) {
            $scope = 'https://graph.microsoft.com/.default'
        }

        # clientId and scope arrive straight off the query string and this endpoint hands back
        # a usable token, so without these guards it brokers a device code login for any
        # application in the operator's tenant. Restrict it to the clients the setup wizard
        # actually drives: Azure PowerShell (used to create the SAM app before one exists),
        # Graph Explorer (the component's fallback when no app id is known yet), and CIPP's
        # own SAM app.
        $AllowedClientIds = [System.Collections.Generic.List[string]]@(
            '1950a258-227b-4e31-a9cf-717495945fc2'
            '1b730954-1685-4b74-9bfd-dac224a7b894'
        )
        if ($env:ApplicationID) { $AllowedClientIds.Add($env:ApplicationID) }

        if ($clientId -notin $AllowedClientIds) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{
                        error             = 'unsupported_client'
                        error_description = "The client id '$clientId' is not permitted for device code logon."
                    } | ConvertTo-Json
                    Headers    = @{'Content-Type' = 'application/json' }
                })
        }

        $InvalidScopes = @($scope -split '\s+' | Where-Object {
                $_ -and $_ -notin @('openid', 'profile', 'email', 'offline_access') -and $_ -notlike 'https://graph.microsoft.com/*'
            })
        if ($InvalidScopes.Count -gt 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{
                        error             = 'invalid_scope'
                        error_description = "Unsupported scope(s) for device code logon: $($InvalidScopes -join ', ')"
                    } | ConvertTo-Json
                    Headers    = @{'Content-Type' = 'application/json' }
                })
        }

        if ($Request.Query.operation -eq 'getDeviceCode') {
            $deviceCodeInfo = New-DeviceLogin -clientid $clientId -scope $scope -FirstLogon -TenantId $tenantId
            if ($deviceCodeInfo.user_code) {
                $Results = @{
                    user_code        = $deviceCodeInfo.user_code
                    device_code      = $deviceCodeInfo.device_code
                    verification_uri = $deviceCodeInfo.verification_uri
                    expires_in       = $deviceCodeInfo.expires_in
                    interval         = $deviceCodeInfo.interval
                    message          = $deviceCodeInfo.message
                }
            } else {
                $Results = @{
                    error             = $deviceCodeInfo.error ?? 'device_code_error'
                    error_description = $deviceCodeInfo.error_description ?? 'Failed to request a device code.'
                }
            }
        } elseif ($Request.Query.operation -eq 'checkToken') {
            $tokenInfo = New-DeviceLogin -clientid $clientId -scope $scope -device_code $deviceCode -TenantId $tenantId

            if ($tokenInfo.refresh_token) {
                # The refresh token is deliberately not returned. Nothing downstream consumes it -
                # the wizard only forwards the access token to ExecCreateSamApp - and returning it
                # would put a long-lived credential into the browser for no reason. The token CIPP
                # runs on is minted by the authorization code step instead.
                $Results = @{
                    status         = 'success'
                    access_token   = $tokenInfo.access_token
                    id_token       = $tokenInfo.id_token
                    expires_in     = $tokenInfo.expires_in
                    ext_expires_in = $tokenInfo.ext_expires_in
                }
            } else {
                # Only authorization_pending and slow_down mean "keep polling". Reporting every
                # failure as pending made terminal errors - an expired code, a declined consent,
                # or a device code flow block from security defaults or a Conditional Access
                # authentication flows policy - look like the user simply had not finished
                # signing in, so the wizard span until the code expired with nothing to show.
                $Status = switch ($tokenInfo.error) {
                    'authorization_pending' { 'pending' }
                    'slow_down' { 'slow_down' }
                    default { 'error' }
                }
                $Results = @{
                    status            = $Status
                    error             = $tokenInfo.error
                    error_description = $tokenInfo.error_description
                }
            }
        }
    } catch {
        # ErrorDetails carries the response body from the token endpoint, which is where the
        # AADSTS code lives; the exception message on its own is just the status line.
        $Results = @{
            error             = 'server_error'
            error_description = "An error occurred: $($_.ErrorDetails.Message ?? $_.Exception.Message)"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results | ConvertTo-Json
            Headers    = @{'Content-Type' = 'application/json' }
        })
}
