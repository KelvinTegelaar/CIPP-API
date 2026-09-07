function Invoke-ExecSendPush {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Sends a test MFA push notification to a user's authenticator app and reports whether it was approved, or - when an OTP code is supplied - verifies that typed code without sending a push. Used to confirm a user's MFA registration works. The push path causes a real prompt on the user's device.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.body.TenantFilter
    $UserEmail = $Request.body.UserEmail
    # When an OTP code is supplied we verify that code instead of sending a push notification.
    $OTP = $Request.body.OTP
    $VerifyOtp = -not [string]::IsNullOrWhiteSpace($OTP)

    # Defaults so every path returns a well-formed state, even when an early step fails.
    $State = 'error'
    $Body = 'An unknown error occurred while processing the MFA request.'
    $obj = $null
    $ResultValue = $null

    # Mint a connector token (this provisions a temporary secret on the MFA client service principal).
    try {
        $Connector = New-CIPPMFAConnectorToken -TenantFilter $TenantFilter -Headers $Request.Headers
    } catch {
        $Body = $_.Exception.Message
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed MFA request for $UserEmail - $Body" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = [pscustomobject]@{'Results' = @{ resultText = $Body; state = 'error' } }
            })
    }

    $ClientHeaders = @{ 'Authorization' = "Bearer $($Connector.AccessToken)" }

    # Policy: a typed code is only accepted when the user has no Microsoft Authenticator registered. When the
    # Authenticator is present the stronger interactive push is required, so a TOTP code is refused.
    $HasAuthenticator = $false
    if ($VerifyOtp) {
        $UserMethods = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserEmail/authentication/methods" -tenantid $TenantFilter
        $HasAuthenticator = @($UserMethods).'@odata.type' -contains '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
    }

    if ($VerifyOtp -and $HasAuthenticator) {
        $Body = 'This user has Microsoft Authenticator registered, so a push notification is required instead of a typed code.'
        $State = 'error'
    } elseif ($VerifyOtp) {
        # OTP verification is a two-call handshake against the modernized StrongAuthenticationService host
        # (the adnotifications host only supports push): Begin with SyncCall=false so no push is sent, then
        # End with the typed code in AdditionalAuthData, keyed to the returned SessionId.
        $StrongAuthUri = 'https://strongauthenticationservice.auth.microsoft.com/StrongAuthenticationService.svc/Connector'
        $ContextId = (New-Guid).Guid
        $BeginXML = @"
<BeginTwoWayAuthenticationRequest>
<Version>1.0</Version>
<UserPrincipalName>$UserEmail</UserPrincipalName>
<Lcid>en-us</Lcid><AuthenticationMethodProperties xmlns:a="http://schemas.microsoft.com/2003/10/Serialization/Arrays"><a:KeyValueOfstringstring><a:Key>OverrideVoiceOtp</a:Key><a:Value>false</a:Value></a:KeyValueOfstringstring></AuthenticationMethodProperties><ContextId>$ContextId</ContextId>
<SyncCall>false</SyncCall><RequireUserMatch>true</RequireUserMatch><CallerName>radius</CallerName><CallerIP>UNKNOWN:</CallerIP></BeginTwoWayAuthenticationRequest>
"@
        $BeginResp = Invoke-RestMethod -Uri "$StrongAuthUri/BeginTwoWayAuthentication" -Method POST -Headers $ClientHeaders -Body $BeginXML -ContentType 'application/xml'
        $SessionId = $BeginResp.BeginTwoWayAuthenticationResponse.SessionId

        if ($SessionId) {
            $EndXML = @"
<EndTwoWayAuthenticationRequest>
<Version>1.0</Version>
<SessionId>$SessionId</SessionId>
<AdditionalAuthData>$OTP</AdditionalAuthData>
</EndTwoWayAuthenticationRequest>
"@
            $obj = Invoke-RestMethod -Uri "$StrongAuthUri/EndTwoWayAuthentication" -Method POST -Headers $ClientHeaders -Body $EndXML -ContentType 'application/xml'
            $ResultValue = $obj.EndTwoWayAuthenticationResponse.Result.Value

            if ($obj.EndTwoWayAuthenticationResponse.AuthenticationResult -eq $true -and $ResultValue -eq 'Success') {
                $Body = 'The MFA code was verified successfully.'
                $State = 'success'
            } elseif ($ResultValue -eq 'OathCodeIncorrect') {
                $Body = 'The MFA code was incorrect. Please check the code and try again.'
                $State = 'error'
            } else {
                $Body = "MFA code verification failed: $ResultValue"
                $State = 'error'
            }
        } else {
            $Body = 'Could not start an MFA verification session. Does the user have an authenticator (OTP) method registered?'
            $State = 'error'
        }
    } else {
        # Push notification: SyncCall=true blocks until the user approves or denies on their device.
        # AuthenticationMethodId forces the Authenticator push so it prompts even when the user's default
        # method is something else (e.g. an OATH code); otherwise the connector targets the default and
        # returns immediately without a prompt.
        $ContextId = (New-Guid).Guid
        $XML = @"
<BeginTwoWayAuthenticationRequest>
<Version>1.0</Version>
<UserPrincipalName>$UserEmail</UserPrincipalName>
<Lcid>en-us</Lcid><AuthenticationMethodId>PhoneAppNotification</AuthenticationMethodId><AuthenticationMethodProperties xmlns:a="http://schemas.microsoft.com/2003/10/Serialization/Arrays"><a:KeyValueOfstringstring><a:Key>OverrideVoiceOtp</a:Key><a:Value>false</a:Value></a:KeyValueOfstringstring></AuthenticationMethodProperties><ContextId>$ContextId</ContextId>
<SyncCall>true</SyncCall><RequireUserMatch>true</RequireUserMatch><CallerName>radius</CallerName><CallerIP>UNKNOWN:</CallerIP></BeginTwoWayAuthenticationRequest>
"@
        $obj = Invoke-RestMethod -Uri 'https://adnotifications.windowsazure.com/StrongAuthenticationService.svc/Connector//BeginTwoWayAuthentication' -Method POST -Headers $ClientHeaders -Body $XML -ContentType 'application/xml'
        $ResultValue = $obj.BeginTwoWayAuthenticationResponse.result.value

        if ($obj.BeginTwoWayAuthenticationResponse.AuthenticationResult -eq $true) {
            $Body = "Received an MFA confirmation: $($ResultValue | Out-String)"
            $State = 'success'
        } else {
            $Body = "Authentication Failed! Does the user have Push/Phone call MFA configured? ErrorCode: $($ResultValue | Out-String)"
            $State = 'error'
        }
    }

    $Results = [pscustomobject]@{'Results' = @{ resultText = $Body; state = $State } }
    $LogAction = if ($VerifyOtp) { 'Verified MFA code' } else { 'Sent push request' }
    Write-LogMessage -headers $Request.Headers -API $APINAME -message "$LogAction for $UserEmail - Result: $($ResultValue | Out-String)" -Sev 'Info'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
