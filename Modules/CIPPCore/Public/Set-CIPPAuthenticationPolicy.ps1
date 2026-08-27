function Set-CIPPAuthenticationPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # TenantFilter (not Tenant) so the scheduler treats this as the protected tenant scope;
        # the alias keeps existing -Tenant callers working
        [Parameter(Mandatory = $true)][Alias('Tenant')]$TenantFilter,
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
        [Parameter()][bool]$FIDO2AttestationEnforced,
        [Parameter()][bool]$FIDO2SelfServiceRegistration,
        [Parameter()][bool]$VoiceIsOfficePhoneAllowed,
        [Parameter()][bool]$SmsIsUsableForSignIn,
        $APIName = 'Set Authentication Policy',
        $Headers
    )

    # Convert bool input to usable string
    $State = if ($Enabled) { 'enabled' } else { 'disabled' }
    # Get current state of the called authentication method and Set state of authentication method to input state
    try {
        $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -tenantid $TenantFilter -AsApp $True
        $CurrentInfo.state = $State
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        # Throw rather than return: callers treat any returned string as a successful write, so returning
        # here made a failed read look like a completed remediation in both the audit log and the API response.
        throw "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($ErrorMessage.NormalizedError)"
    }

    switch ($AuthenticationMethodId) {

        # FIDO2
        'FIDO2' {
            if ($State -eq 'enabled') {
                # Honor passed values; otherwise default to enforced/allowed to preserve previous enable behavior.
                # With passkey profiles present attestation is governed per-profile, and Graph rejects a
                # top-level flag that disagrees with the DEFAULT profile ("Attestation enforcement cannot
                # be enabled when it is disabled in default passkey profile") - align instead of forcing.
                $PasskeyProfiles = @($CurrentInfo.passkeyProfiles | Where-Object { $_ })
                $CurrentInfo.isAttestationEnforced = if ($PSBoundParameters.ContainsKey('FIDO2AttestationEnforced')) { $FIDO2AttestationEnforced }
                elseif ($PasskeyProfiles.Count -gt 0) {
                    $DefaultProfile = @($PasskeyProfiles | Where-Object { "$($_.id)" -eq "$($CurrentInfo.defaultPasskeyProfile)" }) | Select-Object -First 1
                    "$(($DefaultProfile ?? $PasskeyProfiles[0]).attestationEnforcement)" -ne 'disabled'
                } else { $true }
                $CurrentInfo.isSelfServiceRegistrationAllowed = if ($PSBoundParameters.ContainsKey('FIDO2SelfServiceRegistration')) { $FIDO2SelfServiceRegistration } else { $true }
                # Graph validates the whole config on write and requires keyRestrictions on every profile.
                foreach ($PasskeyProfile in $PasskeyProfiles) {
                    if (-not $PasskeyProfile.keyRestrictions) {
                        $PasskeyProfile | Add-Member -NotePropertyName 'keyRestrictions' -NotePropertyValue ([PSCustomObject]@{ isEnforced = $false; enforcementType = 'block'; aaGuids = @() }) -Force
                    }
                }
                $OptionalLogMessage = "with attestation enforced set to $($CurrentInfo.isAttestationEnforced) and self-service registration set to $($CurrentInfo.isSelfServiceRegistrationAllowed)"
            }
        }

        # Microsoft Authenticator
        'MicrosoftAuthenticator' {
            if ($State -eq 'enabled') {
                $AuthChanges = [System.Collections.Generic.List[string]]::new()
                # Set MS authenticator OTP state if parameter is passed in
                if ($null -ne $MicrosoftAuthenticatorSoftwareOathEnabled) {
                    $CurrentInfo.isSoftwareOathEnabled = $MicrosoftAuthenticatorSoftwareOathEnabled
                    $AuthChanges.Add("software OTP set to $MicrosoftAuthenticatorSoftwareOathEnabled")
                }
                # Feature settings
                if ($MicrosoftAuthenticatorDisplayAppInfo) {
                    $CurrentInfo.featureSettings.displayAppInformationRequiredState.state = $MicrosoftAuthenticatorDisplayAppInfo
                    $AuthChanges.Add("display app information set to $MicrosoftAuthenticatorDisplayAppInfo")
                }
                if ($MicrosoftAuthenticatorDisplayLocation) {
                    $CurrentInfo.featureSettings.displayLocationInformationRequiredState.state = $MicrosoftAuthenticatorDisplayLocation
                    $AuthChanges.Add("display location set to $MicrosoftAuthenticatorDisplayLocation")
                }
                if ($MicrosoftAuthenticatorCompanionApp) {
                    $CurrentInfo.featureSettings.companionAppAllowedState.state = $MicrosoftAuthenticatorCompanionApp
                    $AuthChanges.Add("companion app set to $MicrosoftAuthenticatorCompanionApp")
                }
                if ($AuthChanges.Count -gt 0) {
                    $OptionalLogMessage = "with $($AuthChanges -join ', ')"
                }
            }
            # numberMatchingRequiredState is permanently enabled by Microsoft and can no
            # longer be toggled - Graph rejects ANY write that echoes it back. This must
            # strip on BOTH paths: it previously only ran on enable, so every DISABLE
            # echoed the deprecated field and failed.
            $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
        }

        # SMS
        'SMS' {
            # SMS sign-in is set per include-target (smsAuthenticationMethodTarget.isUsableForSignIn)
            if ($State -eq 'enabled' -and $PSBoundParameters.ContainsKey('SmsIsUsableForSignIn')) {
                foreach ($Target in $CurrentInfo.includeTargets) {
                    $Target | Add-Member -NotePropertyName 'isUsableForSignIn' -NotePropertyValue $SmsIsUsableForSignIn -Force
                }
                $OptionalLogMessage = "with SMS sign-in set to $SmsIsUsableForSignIn"
            }
        }

        # Temporary Access Pass
        'TemporaryAccessPass' {
            if ($State -eq 'enabled') {
                $CurrentInfo.isUsableOnce = [System.Convert]::ToBoolean($TAPisUsableOnce)
                $CurrentInfo.minimumLifetimeInMinutes = $TAPMinimumLifetime
                $CurrentInfo.maximumLifetimeInMinutes = $TAPMaximumLifetime
                $CurrentInfo.defaultLifetimeInMinutes = $TAPDefaultLifeTime
                $CurrentInfo.defaultLength = $TAPDefaultLength
                $OptionalLogMessage = "with TAP isUsableOnce set to $TAPisUsableOnce, minimum lifetime $TAPMinimumLifetime min, maximum lifetime $TAPMaximumLifetime min, default lifetime $TAPDefaultLifeTime min, and default length $TAPDefaultLength"
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
            if ($State -eq 'enabled' -and $PSBoundParameters.ContainsKey('VoiceIsOfficePhoneAllowed')) {
                $CurrentInfo.isOfficePhoneAllowed = $VoiceIsOfficePhoneAllowed
                $OptionalLogMessage = "with isOfficePhoneAllowed set to $VoiceIsOfficePhoneAllowed"
            }
        }

        # Email OTP
        'Email' {
            if ($State -eq 'enabled') {
                if ($EmailAllowExternalIdToUseEmailOtp) {
                    $CurrentInfo.allowExternalIdToUseEmailOtp = $EmailAllowExternalIdToUseEmailOtp
                    $OptionalLogMessage = "with allowExternalIdToUseEmailOtp set to $EmailAllowExternalIdToUseEmailOtp"
                }
                # Present (even empty) means the caller is setting the exclude list; an empty array clears it
                if ($PSBoundParameters.ContainsKey('EmailExcludeGroupIds')) {
                    $CurrentInfo.excludeTargets = @(
                        foreach ($id in $EmailExcludeGroupIds) {
                            [pscustomobject]@{
                                targetType = 'group'
                                id         = $id
                            }
                        }
                    )
                    if ($EmailExcludeGroupIds) {
                        $OptionalLogMessage += " and excluded groups set to $($EmailExcludeGroupIds -join ', ')"
                    } else {
                        $OptionalLogMessage += ' and excluded groups cleared'
                    }
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
                $OptionalLogMessage = "with QR code lifetime $QRCodeLifetimeInDays days and PIN length $QRCodePinLength"
            }
        }
        default {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Somehow you hit the default case with an input of $AuthenticationMethodId . You probably made a typo in the input for AuthenticationMethodId. It`'s case sensitive." -sev Error
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
            $null = New-GraphPostRequest -tenantid $TenantFilter -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -Type PATCH -Body (ConvertTo-Json -InputObject $CurrentInfo -Compress -Depth 10) -ContentType 'application/json' -AsApp $True
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set $AuthenticationMethodId state to $State $OptionalLogMessage" -sev Info
        }
        return "Set $AuthenticationMethodId state to $State $OptionalLogMessage"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $ErrorMessage" -sev Error -LogData $ErrorMessage
        throw "Failed to $State $AuthenticationMethodId Support. Error: $($ErrorMessage.NormalizedError)"
    }
}
