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
        if ($Request.Query.operation -eq 'getDeviceCode') {
            $deviceCodeInfo = New-DeviceLogin -clientid $clientId -scope $scope -FirstLogon -TenantId $tenantId
            $Results = @{
                user_code        = $deviceCodeInfo.user_code
                device_code      = $deviceCodeInfo.device_code
                verification_uri = $deviceCodeInfo.verification_uri
                expires_in       = $deviceCodeInfo.expires_in
                interval         = $deviceCodeInfo.interval
                message          = $deviceCodeInfo.message
            }
        } elseif ($Request.Query.operation -eq 'checkToken') {
            $tokenInfo = New-DeviceLogin -clientid $clientId -scope $scope -device_code $deviceCode

            if ($tokenInfo.refresh_token) {
                $Results = @{
                    status         = 'success'
                    access_token   = $tokenInfo.access_token
                    refresh_token  = $tokenInfo.refresh_token
                    id_token       = $tokenInfo.id_token
                    expires_in     = $tokenInfo.expires_in
                    ext_expires_in = $tokenInfo.ext_expires_in
                }
            } else {
                $Results = @{
                    status            = 'pending'
                    error             = $tokenInfo.error
                    error_description = $tokenInfo.error_description
                }
            }
        }
    } catch {
        $Results = @{
            error             = 'server_error'
            error_description = "An error occurred: $($_.Exception.Message)"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results | ConvertTo-Json
            Headers    = @{'Content-Type' = 'application/json' }
        })
}
