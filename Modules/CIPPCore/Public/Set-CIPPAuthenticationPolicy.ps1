function Set-CIPPAuthenticationPolicy {
    [CmdletBinding()]
    param(
        $TenantFilter,
        [Parameter(Mandatory = $true)]$AuthenticationMethodId,
        [Parameter(Mandatory = $true)][bool]$State, # true = enabled or false = disabled
        [bool]$MicrosoftAuthenticatorSoftwareOathEnabled, 
        $TAPMinimumLifetime = 60, #Minutes
        $TAPMaximumLifetime = 480, #minutes
        $TAPDefaultLifeTime = 60, #minutes
        $TAPDefaultLength = 8, #TAP password generated length in chars
        [bool]$TAPisUsableOnce = $true,
        $APIName = 'Set Authentication Policy',
        $ExecutingUser = 'None'
    )

    # Convert bool input to usable string
    $State = if ($State) { 'enabled' } else { 'disabled' }

    # Get current state of the called authentication method and Set state of authentication method to input state
    try {
        $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -tenantid $Tenant
        $CurrentInfo.state = $State
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Could not get CurrentInfo for $AuthenticationMethodId. Error:$($_.exception.message)" -sev Error
    }
    
    switch ($AuthenticationMethodId) {
        
        # FIDO2
        'FIDO2' {
            # Craft the body for FIDO2
            $CurrentInfo = [PSCustomObject]@{
                '@odata.type'                    = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
                id                               = 'Fido2'
                includeTargets                   = @(@{
                        id                     = 'all_users'
                        isRegistrationRequired = $false
                        targetType             = 'group'
                        displayName            = 'All users'
                    })
                    
                excludeTargets                   = @()
                isAttestationEnforced            = $true
                isSelfServiceRegistrationAllowed = $true
                keyRestrictions                  = @{
                    aaGuids         = @()
                    enforcementType = 'block'
                    isEnforced      = $false
                }
                state                            = $State
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
                if ($null -ne $MicrosoftAuthenticatorSoftwareOathEnabled ) { $CurrentInfo.isSoftwareOathEnabled = $MicrosoftAuthenticatorSoftwareOathEnabled }
            }
        }
        # SMS
        'SMS' {  
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
            }
        }
        # Temporary Access Pass
        'TemporaryAccessPass' {  

            if ($State -eq 'enabled') {
                $CurrentInfo.isUsableOnce = $TAPisUsableOnce
                $CurrentInfo.minimumLifetimeInMinutes = $TAPMinimumLifetime
                $CurrentInfo.maximumLifetimeInMinutes = $TAPMaximumLifetime
                $CurrentInfo.defaultLifetimeInMinutes = $TAPDefaultLifeTime
                $CurrentInfo.defaultLength = $TAPDefaultLength
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
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
            }
        }
    
        # Email OTP
        'Email' {  
            if ($State -eq 'enabled') {
                Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Setting $AuthenticationMethodId to enabled is not allowed" -sev Error
                return "Setting $AuthenticationMethodId to enabled is not allowed"
            }
        }
        # Certificate-based authentication
        'x509Certificate' {  
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "$AuthenticationMethodId is not yet supported in CIPP" -sev Error
            return "$AuthenticationMethodId is not yet supported in CIPP"
        }
        Default {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message 'Somehow you hit the default case. You probably made a type in the input for AuthenticationMethodId. It''s case sensitive' -sev Error
            return 'Somehow you hit the default case. You probably made a type in the input for AuthenticationMethodId. It''s case sensitive.'
        }

        # Set state of the authentication method
        try {
            # Convert body to JSON and send request
            $body = ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo
            New-GraphPostRequest -tenantid $TenantFilter -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$AuthenticationMethodId" -Type patch -Body $body -ContentType 'application/json'
        
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Set $AuthenticationMethodId state to $State" -sev Info
            return "Set $AuthenticationMethodId state to $State"
        }
        catch {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            return "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)"
        }
    }
}