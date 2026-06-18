function Set-CIPPAuthenticationPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Tenant,
        [Parameter(Mandatory = $true)][ValidateSet('FIDO2', 'MicrosoftAuthenticator', 'SMS', 'TemporaryAccessPass', 'HardwareOATH', 'softwareOath', 'Voice', 'Email', 'x509Certificate', 'QRCodePin')]$AuthenticationMethodId,
        [Parameter(Mandatory = $true)][bool]$Enabled, # true = enabled or false = disabled
        $MicrosoftAuthenticatorSoftwareOathEnabled,
        [ValidateSet('default', 'enabled', 'disabled')]$MicrosoftAuthenticatorDisplayLocation,
        [ValidateSet('default', 'enabled', 'disabled')]$MicrosoftAuthenticatorDisplayAppInfo,
        [ValidateSet('default', 'enabled', 'disabled')]$MicrosoftAuthenticatorCompanionApp,
        $TAPMinimumLifetime = 60, #Minutes
        $TAPMaximumLifetime = 480, #minutes
        $TAPDefaultLifeTime = 60, #minutes
        $TAPDefaultLength = 8, #TAP password generated length in chars
        $TAPisUsableOnce = $true,
        [Parameter()][string[]]$GroupIds,
        [Parameter()][ValidateRange(1, 395)]$QRCodeLifetimeInDays = 365,
        [Parameter()][ValidateRange(8, 20)]$QRCodePinLength = 8,
        [Parameter()][ValidateSet('default', 'enabled', 'disabled')]$EmailAllowExternalIdToUseEmailOtp,
        [Parameter()][string[]]$EmailExcludeGroupIds,
        $APIName = 'Set Authentication Policy',
        $Headers
    )

    # Convert bool input to usable string
    $State = if ($Enabled) { 'enabled' } else { 'disabled' }
    # Get current state of the called authentication method and Set state of authentication method to input state
    try {
        $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -tenantid $Tenant -AsApp $True
        $CurrentInfo.state = $State
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($ErrorMessage.NormalizedError)"
    }

    switch ($AuthenticationMethodId) {

        # FIDO2
        'FIDO2' {
            if ($State -eq 'enabled') {
                $CurrentInfo.isAttestationEnforced = $true
                $CurrentInfo.isSelfServiceRegistrationAllowed = $true
            }
        }

        # Microsoft Authenticator
        'MicrosoftAuthenticator' {
            if ($State -eq 'enabled') {
                # Set MS authenticator OTP state if parameter is passed in
                if ($null -ne $MicrosoftAuthenticatorSoftwareOathEnabled) {
                    $CurrentInfo.isSoftwareOathEnabled = $MicrosoftAuthenticatorSoftwareOathEnabled
                    $OptionalLogMessage = "and MS Authenticator software OTP to $MicrosoftAuthenticatorSoftwareOathEnabled"
                }
                # Feature settings
                if ($MicrosoftAuthenticatorDisplayAppInfo) {
                    $CurrentInfo.featureSettings.displayAppInformationRequiredState.state = $MicrosoftAuthenticatorDisplayAppInfo
                }
                if ($MicrosoftAuthenticatorDisplayLocation) {
                    $CurrentInfo.featureSettings.displayLocationInformationRequiredState.state = $MicrosoftAuthenticatorDisplayLocation
                }
                if ($MicrosoftAuthenticatorCompanionApp) {
                    $CurrentInfo.featureSettings.companionAppAllowedState.state = $MicrosoftAuthenticatorCompanionApp
                }
                # numberMatchingRequiredState is permanently enabled by Microsoft and can no longer be toggled
                $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
            }
        }

        # SMS
        'SMS' {
            # No special configuration needed
        }

        # Temporary Access Pass
        'TemporaryAccessPass' {
            if ($State -eq 'enabled') {
                $CurrentInfo.isUsableOnce = [System.Convert]::ToBoolean($TAPisUsableOnce)
                $CurrentInfo.minimumLifetimeInMinutes = $TAPMinimumLifetime
                $CurrentInfo.maximumLifetimeInMinutes = $TAPMaximumLifetime
                $CurrentInfo.defaultLifetimeInMinutes = $TAPDefaultLifeTime
                $CurrentInfo.defaultLength = $TAPDefaultLength
                $OptionalLogMessage = "with TAP isUsableOnce set to $TAPisUsableOnce"
            }
        }

        # Hardware OATH tokens (Preview)
        'HardwareOATH' {
            # Nothing special to do here
        }

        # Third-party software OATH tokens
        'softwareOath' {
            # Nothing special to do here
        }

        # Voice call
        'Voice' {
            # No special configuration needed
        }

        # Email OTP
        'Email' {
            if ($State -eq 'enabled') {
                if ($EmailAllowExternalIdToUseEmailOtp) {
                    $CurrentInfo.allowExternalIdToUseEmailOtp = $EmailAllowExternalIdToUseEmailOtp
                    $OptionalLogMessage = "with allowExternalIdToUseEmailOtp set to $EmailAllowExternalIdToUseEmailOtp"
                }
                if ($EmailExcludeGroupIds) {
                    $CurrentInfo.excludeTargets = @(
                        foreach ($id in $EmailExcludeGroupIds) {
                            [pscustomobject]@{
                                targetType = 'group'
                                id         = $id
                            }
                        }
                    )
                    $OptionalLogMessage += " and excluded groups set to $($EmailExcludeGroupIds -join ', ')"
                }
            }
        }

        # Certificate-based authentication
        'x509Certificate' {
            # No special configuration needed
        }

        # QR code
        'QRCodePin' {
            if ($State -eq 'enabled') {
                $CurrentInfo.standardQRCodeLifetimeInDays = $QRCodeLifetimeInDays
                $CurrentInfo.pinLength = $QRCodePinLength
            }
        }
        default {
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Somehow you hit the default case with an input of $AuthenticationMethodId . You probably made a typo in the input for AuthenticationMethodId. It`'s case sensitive." -sev Error
            throw "Somehow you hit the default case with an input of $AuthenticationMethodId . You probably made a typo in the input for AuthenticationMethodId. It`'s case sensitive."
        }
    }

    if ($PSBoundParameters.ContainsKey('GroupIds') -and $GroupIds) {
        $CurrentInfo.includeTargets = @(
            foreach ($id in $GroupIds ) {
                [pscustomobject]@{
                    targetType = 'group'
                    id         = $id
                }
            }
        )
        $OptionalLogMessage += " and targeted groups set to $($CurrentInfo.includeTargets.id -join ', ')"
    }


    # Set state of the authentication method
    try {
        if ($PSCmdlet.ShouldProcess($AuthenticationMethodId, "Set state to $State $OptionalLogMessage")) {
            # Convert body to JSON and send request
            $null = New-GraphPostRequest -tenantid $Tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -Type PATCH -Body (ConvertTo-Json -InputObject $CurrentInfo -Compress -Depth 10) -ContentType 'application/json' -AsApp $True
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Set $AuthenticationMethodId state to $State $OptionalLogMessage" -sev Info
        }
        return "Set $AuthenticationMethodId state to $State $OptionalLogMessage"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to $State $AuthenticationMethodId Support: $ErrorMessage" -sev Error -LogData $ErrorMessage
        throw "Failed to $State $AuthenticationMethodId Support. Error: $($ErrorMessage.NormalizedError)"
    }
}
