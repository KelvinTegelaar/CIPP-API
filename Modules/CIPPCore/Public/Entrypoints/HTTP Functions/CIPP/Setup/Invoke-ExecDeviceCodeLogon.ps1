using namespace System.Net

function Invoke-ExecDeviceCodeLogon {
    <#
    .SYNOPSIS
    Execute device code authentication flow for CIPP setup
    
    .DESCRIPTION
    Handles device code authentication flow for CIPP setup including generating device codes and checking token status for OAuth authentication
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
        
    .NOTES
    Group: CIPP Setup
    Summary: Exec Device Code Logon
    Description: Handles device code authentication flow for CIPP setup including generating device codes and checking token status for OAuth authentication with Microsoft Graph API
    Tags: Setup,Authentication,Device Code,OAuth
    Parameter: clientId (string) [query] - Application client ID for authentication
    Parameter: scope (string) [query] - OAuth scope (defaults to https://graph.microsoft.com/.default)
    Parameter: tenantId (string) [query] - Target tenant ID for authentication
    Parameter: deviceCode (string) [query] - Device code for token checking
    Parameter: operation (string) [query] - Operation to perform: getDeviceCode or checkToken
    Response: Returns different objects based on operation:
    Response: For getDeviceCode operation:
    Response: - user_code (string): User code to enter on device
    Response: - device_code (string): Device code for polling
    Response: - verification_uri (string): URI for device verification
    Response: - expires_in (number): Expiration time in seconds
    Response: - interval (number): Polling interval in seconds
    Response: - message (string): User-friendly message
    Response: For checkToken operation (success):
    Response: - status (string): "success"
    Response: - access_token (string): OAuth access token
    Response: - refresh_token (string): OAuth refresh token
    Response: - id_token (string): OAuth ID token
    Response: - expires_in (number): Token expiration time
    Response: - ext_expires_in (number): Extended expiration time
    Response: For checkToken operation (pending):
    Response: - status (string): "pending"
    Response: - error (string): Error code if any
    Response: - error_description (string): Error description
    Response: On error: Error object with server_error and description
    Example: {
      "user_code": "ABCD-EFGH",
      "device_code": "device_code_123",
      "verification_uri": "https://microsoft.com/devicelogin",
      "expires_in": 900,
      "interval": 5,
      "message": "To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ABCD-EFGH to authenticate."
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

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
        }
        elseif ($Request.Query.operation -eq 'checkToken') {
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
            }
            else {
                $Results = @{
                    status            = 'pending'
                    error             = $tokenInfo.error
                    error_description = $tokenInfo.error_description
                }
            }
        }
    }
    catch {
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
