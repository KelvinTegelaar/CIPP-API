function Invoke-CIPPStandardallowOAuthTokens {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = new-graphgetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $Tenant
    If ($Settings.remediate) {
        
        try {
            $CurrentInfo.state = 'enabled'
            $body = ($CurrentInfo | ConvertTo-Json -Depth 10)
    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -Type patch -Body $body -ContentType 'application/json')

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled software OTP/oAuth tokens' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable software OTP/oAuth tokens. Error: $($_.exception.message)" -sev 'Error'
        }
    }
    if ($Settings.alert) {

        if ($CurrentInfo.state -eq 'enabled') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'software OTP/oAuth tokens is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'software OTP/oAuth tokens is not enabled' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($CurrentInfo.state -eq 'enabled') {
            $CurrentInfo.state = $true
        } else {
            $CurrentInfo.state = $false
        }
        Add-CIPPBPAField -FieldName 'softwareOath' -FieldValue [bool]$CurrentInfo.state -StoreAs bool -Tenant $tenant
    }
}
