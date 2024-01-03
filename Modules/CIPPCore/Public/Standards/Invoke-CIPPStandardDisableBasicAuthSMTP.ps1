function Invoke-CIPPStandardDisableBasicAuthSMTP {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        
        # Disable SMTP Basic Authentication for the tenant
        try {
            $Request = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportConfig' -cmdParams @{ SmtpClientAuthenticationDisabled = $true }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled SMTP Basic Authentication' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication: $($_.exception.message)" -sev Error
        }

        # Disable SMTP Basic Authentication for all users
        $SMTPusers = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-CASMailbox' -cmdParams @{ ResultSize = 'Unlimited' } | Where-Object { ($null -ne $_.SmtpClientAuthenticationDisabled) }
        $SMTPusers | ForEach-Object {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $_.Identity; SmtpClientAuthenticationDisabled = $null } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress). Error: $($_.exception.message)" -sev Error
                
            }
        }
    }
    

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig'

        if ($Settings.alert) {
            if ($CurrentInfo.SmtpClientAuthenticationDisabled) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication is disabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication is not disabled' -sev Alert
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue [bool]$CurrentInfo.SmtpClientAuthenticationDisabled -StoreAs bool -Tenant $tenant
        }
    }
}
