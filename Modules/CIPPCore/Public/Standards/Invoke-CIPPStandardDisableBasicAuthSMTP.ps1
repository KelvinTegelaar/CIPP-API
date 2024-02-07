function Invoke-CIPPStandardDisableBasicAuthSMTP {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig'
    $SMTPusers = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-CASMailbox' -cmdParams @{ ResultSize = 'Unlimited' } | Where-Object { ($_.SmtpClientAuthenticationDisabled -eq $false) }

    If ($Settings.remediate) {
        
        if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication for tenant and all users is already disabled' -sev Info
        } else {
            # Disable SMTP Basic Authentication for the tenant
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportConfig' -cmdParams @{ SmtpClientAuthenticationDisabled = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled SMTP Basic Authentication' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication: $($_.exception.message)" -sev Error
            }
    
            # Disable SMTP Basic Authentication for all users
            $SMTPusers | ForEach-Object {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $_.Identity; SmtpClientAuthenticationDisabled = $null } -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress)" -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress). Error: $($_.exception.message)" -sev Error
                }
            }
        }
    }

    if ($Settings.alert) {
        if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication for tenant and all users is disabled' -sev Info
        } else {
            
            if ($CurrentInfo.SmtpClientAuthenticationDisabled) {
                $LogMessage = 'SMTP Basic Authentication for tenant is disabled. '
            } else {
                $LogMessage = 'SMTP Basic Authentication for tenant is not disabled. '
            }
            if ($SMTPusers.Count -eq 0) {
                $LogMessage += 'SMTP Basic Authentication for all users is disabled'
            } else {
                $LogMessage += "SMTP Basic Authentication for $($SMTPusers.Count) users is not disabled"
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message $LogMessage -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue [bool]$CurrentInfo.SmtpClientAuthenticationDisabled -StoreAs bool -Tenant $tenant
    }
}
