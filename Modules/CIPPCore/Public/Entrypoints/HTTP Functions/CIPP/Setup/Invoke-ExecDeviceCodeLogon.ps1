using namespace System.Net

Function Invoke-ExecDeviceCodeLogon {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $UserCreds = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json)
    if ('admin' -notin $UserCreds.userRoles) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                ContentType = 'application/json'
                StatusCode  = [HttpStatusCode]::Forbidden
                Body        = @{
                    error        = 'Forbidden'
                    errorMessage = 'You do not have permission to perform this action'
                } | ConvertTo-Json
            })
        exit
    }

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results | ConvertTo-Json
            Headers    = @{'Content-Type' = 'application/json' }
        })
}
