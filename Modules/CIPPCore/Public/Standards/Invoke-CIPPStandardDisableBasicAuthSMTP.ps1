function Invoke-CIPPStandardDisableBasicAuthSMTP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableBasicAuthSMTP
    .SYNOPSIS
        (Label) Disable SMTP Basic Authentication
    .DESCRIPTION
        (Helptext) Disables SMTP AUTH for the organization and all users. This is the default for new tenants. 
        (DocsDescription) Disables SMTP basic authentication for the tenant and all users with it explicitly enabled.
    .NOTES
        CAT
            Global Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-TransportConfig -SmtpClientAuthenticationDisabled $true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig'
    $SMTPusers = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-CASMailbox' -cmdParams @{ ResultSize = 'Unlimited' } | Where-Object { ($_.SmtpClientAuthenticationDisabled -eq $false) }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication for tenant and all users is already disabled' -sev Info
        } else {
            # Disable SMTP Basic Authentication for the tenant
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportConfig' -cmdParams @{ SmtpClientAuthenticationDisabled = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled SMTP Basic Authentication' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication. Error: $ErrorMessage" -sev Error
            }

            # Disable SMTP Basic Authentication for all users
            $SMTPusers | ForEach-Object {
                try {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $_.Identity; SmtpClientAuthenticationDisabled = $null } -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress)" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication for $($_.DisplayName), $($_.PrimarySmtpAddress). Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    $LogMessage = [System.Collections.Generic.List[string]]::new()
    if ($Settings.alert -eq $true -or $Settings.report -eq $true) {

        # Build the log message for use in the alert and report
        if ($CurrentInfo.SmtpClientAuthenticationDisabled) {
            $LogMessage.add('SMTP Basic Authentication for tenant is disabled. ')
        } else {
            $LogMessage.add('SMTP Basic Authentication for tenant is not disabled. ')
        }
        if ($SMTPusers.Count -eq 0) {
            $LogMessage.add('SMTP Basic Authentication for all users is disabled')
        } else {
            $LogMessage.add("SMTP Basic Authentication for the following $($SMTPusers.Count) users is not disabled: $($SMTPusers.PrimarySmtpAddress -join ',')")
        }

        if ($Settings.alert -eq $true) {

            if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication for tenant and all users is disabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message $LogMessage -sev Alert
            }
        }

        if ($Settings.report -eq $true) {

            if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
                Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue $CurrentInfo.SmtpClientAuthenticationDisabled -StoreAs bool -Tenant $tenant
            } else {
                Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue $LogMessage -StoreAs string -Tenant $tenant
            }
        }
    }
}
