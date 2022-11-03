param($tenant)

try {
    $body = @"
{"@odata.context":"https://graph.microsoft.com/beta/$metadata#authenticationMethodConfigurations/$entity","@odata.type":"#microsoft.graph.microsoftAuthenticatorAuthenticationMethodConfiguration","id":"MicrosoftAuthenticator","state":"enabled","featureSettings":{"numberMatchingRequiredState":{"state":"enabled","includeTarget":{"targetType":"group","id":"all_users"},"excludeTarget":{"targetType":"group","id":"00000000-0000-0000-0000-000000000000"}}},"includeTargets@odata.context":"https://graph.microsoft.com/beta/$metadata#authenticationMethodsPolicy/authenticationMethodConfigurations('MicrosoftAuthenticator')/microsoft.graph.microsoftAuthenticatorAuthenticationMethodConfiguration/includeTargets","includeTargets":[{"targetType":"group","id":"all_users","isRegistrationRequired":false,"authenticationMode":"any",}]}
"@
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage  -API "Standards" -tenant $tenant -message "Enabled passwordless with Number Matching." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable passwordless with Number Matching. Error: $($_.exception.message)"
}