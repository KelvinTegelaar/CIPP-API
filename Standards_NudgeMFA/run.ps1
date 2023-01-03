param($tenant)

try {
    $body = '{"registrationEnforcement":{"authenticationMethodsRegistrationCampaign":{"snoozeDurationInDays":0,"state":"enabled","excludeTargets":[],"includeTargets":[{"id":"all_users","targetType":"group","targetedAuthenticationMethod":"microsoftAuthenticator","displayName":"All users"}]}}}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Enabled Authenticator App Nudge" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to enable Authenticator App Nudge: $($_.exception.message)" -sev Error
}