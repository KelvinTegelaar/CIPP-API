param($tenant)

try {

    $CurrentInfo = new-graphgetRequest -uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -tenantid $Tenant
    $CurrentInfo.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
    $CurrentInfo.featureSettings.displayAppInformationRequiredState.state = "enabled"
    $CurrentInfo.featureSettings.displayLocationInformationRequiredState.state = "enabled"
    $body = ($CurrentInfo | ConvertTo-Json -depth 10)
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage  -API "Standards" -tenant $tenant -message "Enabled passwordless with Information and Number Matching." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable passwordless with Information and Number Matching. Error: $($_.exception.message)" -sev "Error"
}