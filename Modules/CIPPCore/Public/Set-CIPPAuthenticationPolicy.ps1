function Set-CIPPAuthenticationPolicy {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $AuthenticationMethodId,
        $EnableGroups, # Not sure if i need this, but it's for if the all_users is not the target for enablement
        $OptionalInput, # Used for stuff like the 
        $APIName = 'Set Authentication Policy',
        $ExecutingUser,
        $State # enabled or disabled
    )
        
    switch ($AuthenticationMethodId) {

        # FIDO2
        'FIDO2' {

            if ($State -eq 'enabled') {
                # Enable FIDO2
                try {
                    $body = '{"@odata.type":"#microsoft.graph.fido2AuthenticationMethodConfiguration","id":"Fido2","includeTargets":[{"id":"all_users","isRegistrationRequired":false,"targetType":"group","displayName":"All users"}],"excludeTargets":[],"isAttestationEnforced":true,"isSelfServiceRegistrationAllowed":true,"keyRestrictions":{"aaGuids":[],"enforcementType":"block","isEnforced":false},"state":"enabled"}'
                    New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -Type patch -Body $body -ContentType 'application/json'
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Enabled $AuthenticationMethodId Support" -sev Info
                }
                catch {
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            # Disable FIDO2
            elseif ($State -eq 'disabled') {
                try {
                    # Get current state and disable
                    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2' -tenantid $TenantFilter
                    $GraphRequest.state = $State
                    $body = ($GraphRequest | ConvertTo-Json -Depth 10)
                    $GraphRequest = New-GraphPostRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2' -Type patch -Body $body -ContentType 'application/json'
    
                }
                catch {
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
                }
            }
            # Catch invalid input
            else {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error
            }

        }

        # Microsoft Authenticator
        'MicrosoftAuthenticator' {  

        }
        # SMS
        'SMS' {  

        }
        # Temporary Access Pass
        'TemporaryAccessPass' {  
            
        }
        # Hardware OATH tokens (Preview)
        'HardwareOATH' {  

        }
        # Third-party software OATH tokens
        'softwareOath' {  

        }
        # Voice call
        'Voice' {  

        }
        # Email OTP
        'Email' {  

        }
        # Certificate-based authentication
        'x509Certificate' {  
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to $State $AuthenticationMethodId Support: $($_.exception.message)" -sev Error

        }
        Default {
            Write-LogMessage -API $APIName -tenant $TenantFilter -message 'Somehow you hit the default case. You did something wrong' -sev Error
            return 'Somehow you hit the default case. You did something wrong'
        }
    }











}