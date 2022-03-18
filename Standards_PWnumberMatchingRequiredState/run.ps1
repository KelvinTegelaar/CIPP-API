param($tenant)

try {
    $body = @"
    {"@odata.context":"https://graph.microsoft.com/beta/$metadata#authenticationMethodConfigurations/$entity","@odata.type":"#microsoft.graph.microsoftAuthenticatorAuthenticationMethodConfiguration","id":"MicrosoftAuthenticator","state":"enabled","includeTargets@odata.context":"https://graph.microsoft.com/beta/$metadata#policies/authenticationMethodsPolicy/authenticationMethodConfigurations('MicrosoftAuthenticator')/microsoft.graph.microsoftAuthenticatorAuthenticationMethodConfiguration/includeTargets","includeTargets":[{"targetType":"group","id":"all_users","isRegistrationRequired":false,"authenticationMode":"any","outlookMobileAllowedState":"default","displayAppInformationRequiredState":"default","numberMatchingRequiredState":"enabled"}]}
"@
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type patch -Body $body -ContentType "application/json")

    Log-request  -API "Standards" -tenant $tenant -message "Enabled passwordless with Number Matching." -sev Info
}
catch {
    Log-request  -API "Standards" -tenant $tenant -message "Failed to enable passwordless with Number Matching. Error: $($_.exception.message)"
}