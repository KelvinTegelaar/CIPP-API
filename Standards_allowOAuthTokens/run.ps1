param($tenant)

try {

    $CurrentInfo = new-graphgetRequest -uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath" -tenantid $Tenant
    $CurrentInfo.state = "enabled"
    $body = ($CurrentInfo | ConvertTo-Json -Depth 10)
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage  -API "Standards" -tenant $tenant -message "Enabled software OTP/oAuth tokens" -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable software OTP/oAuth tokens. Error: $($_.exception.message)" -sev "Error"
}