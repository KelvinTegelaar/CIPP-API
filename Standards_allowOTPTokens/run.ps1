param($tenant)

try {

    $CurrentInfo = new-graphgetRequest -uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -tenantid $Tenant
    $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
    $CurrentInfo.isSoftwareOathEnabled = $true
    $body = ($CurrentInfo | ConvertTo-Json -Depth 10)
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage -API "Standards" -tenant $tenant -message "Enabled MS authenticator OTP/oAuth tokens" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to enable MS authenticator OTP/oAuth tokens. Error: $($_.exception.message)" -sev Error
}