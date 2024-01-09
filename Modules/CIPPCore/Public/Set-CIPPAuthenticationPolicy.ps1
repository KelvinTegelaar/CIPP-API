function Set-CIPPAuthenticationPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tenant,
        [Parameter(Mandatory = $true)][ValidateSet('FIDO2', 'MicrosoftAuthenticator', 'SMS', 'TemporaryAccessPass', 'HardwareOATH', 'softwareOath', 'Voice', 'Email', 'x509Certificate')]$AuthenticationMethodId,
        [Parameter(Mandatory = $true)][bool]$Enabled, # true = enabled or false = disabled
        $MicrosoftAuthenticatorSoftwareOathEnabled, 
        $TAPMinimumLifetime = 60, #Minutes
        $TAPMaximumLifetime = 480, #minutes
        $TAPDefaultLifeTime = 60, #minutes
        $TAPDefaultLength = 8, #TAP password generated length in chars
        $TAPisUsableOnce = $true,
        $APIName = 'Set Authentication Policy',
        $ExecutingUser
    )

    # Convert bool input to usable string
    $State = if ($Enabled) { 'enabled' } else { 'disabled' }
    # Get current state of the called authentication method and Set state of authentication method to input state
    try {
        $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -tenantid $Tenant
        $CurrentInfo.state = $State
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($_.exception.message)" -sev Error
        Return "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($_.exception.message)"
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
            # Remove numberMatchingRequiredState property if it exists
            $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
            
            if ($State -eq 'enabled') {
                $CurrentInfo.featureSettings.displayAppInformationRequiredState.state = $State
                $CurrentInfo.featureSettings.displayLocationInformationRequiredState.state = $State
                # Set MS authenticator OTP state if parameter is passed in
                if ($null -ne $MicrosoftAuthenticatorSoftwareOathEnabled ) { 
                    $CurrentInfo.isSoftwareOathEnabled = $MicrosoftAuthenticatorSoftwareOathEnabled 
                    $OptionalLogMessage = "and MS Authenticator software OTP to $MicrosoftAuthenticatorSoftwareOathEnabled"
                }
            }
        }

        # SMS
        'SMS' {  
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
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
            # Disallow enabling voice
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
            }
        }
    
        # Email OTP
        'Email' {  
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
            }
        }
        
        # Certificate-based authentication
        'x509Certificate' {  
            # Nothing special to do here
        }
        Default {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Somehow you hit the default case with an input of $AuthenticationMethodId . You probably made a typo in the input for AuthenticationMethodId. It`'s case sensitive." -sev Error
            return "Somehow you hit the default case with an input of $AuthenticationMethodId . You probably made a typo in the input for AuthenticationMethodId. It`'s case sensitive."
        }
    }
    # Set state of the authentication method
    try {
        # Convert body to JSON and send request
        $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
        New-GraphPostRequest -tenantid $Tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -Type patch -Body $body -ContentType 'application/json'
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Set $AuthenticationMethodId state to $State $OptionalLogMessage" -sev Info
        return "Set $AuthenticationMethodId state to $State $OptionalLogMessage"
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $Tenant -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
        return "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)"
    }
}