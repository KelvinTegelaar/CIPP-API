function Invoke-CIPPStandardDisableBasicAuthSMTP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableBasicAuthSMTP
    .SYNOPSIS
        (Label) Disable SMTP Basic Authentication
    .DESCRIPTION
        (Helptext) Disables SMTP AUTH organization-wide, impacting POP and IMAP clients that rely on SMTP for sending emails. Default for new tenants. For more information, see the [Microsoft documentation](https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission)
        (DocsDescription) Disables tenant-wide SMTP basic authentication, including for all explicitly enabled users, impacting POP and IMAP clients that rely on SMTP for sending emails. For more information, see the [Microsoft documentation](https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission).
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS M365 5.0 (6.5.4)"
            "NIST CSF 2.0 (PR.IR-01)"
        EXECUTIVETEXT
            Disables outdated email authentication methods that are vulnerable to security attacks, forcing applications and devices to use modern, more secure authentication protocols. This reduces the risk of email-based security breaches and credential theft.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Set-TransportConfig -SmtpClientAuthenticationDisabled \$true
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableBasicAuthSMTP' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableBasicAuthSMTP'

    try {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportConfig'
        $SMTPusers = New-CippDbRequest -TenantFilter $Tenant -Type 'CASMailbox' | Where-Object { ($_.SmtpClientAuthenticationDisabled -eq $false) }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableBasicAuthSMTP state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
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

            # Disable SMTP Basic Authentication for all users using bulk request
            if ($SMTPusers.Count -gt 0) {
                $BulkRequest = foreach ($User in $SMTPusers) {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-CASMailbox'
                            Parameters = @{ Identity = $User.Guid; SmtpClientAuthenticationDisabled = $null }
                        }
                    }
                }
                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($BulkRequest) -useSystemMailbox $true
                foreach ($Result in $BatchResults) {
                    if ($Result.error) {
                        $ErrorMessage = Get-NormalizedError -Message $Result.error
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SMTP Basic Authentication for $($Result.target). Error: $ErrorMessage" -sev Error
                    }
                }
                $SuccessCount = ($BatchResults | Where-Object { -not $_.error }).Count
                if ($SuccessCount -gt 0) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled SMTP Basic Authentication for $SuccessCount users" -sev Info
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
            $LogMessage.add("SMTP Basic Authentication for the following $($SMTPusers.Count) users is not disabled: $($SMTPusers.PrimarySmtpAddress -join ', ')")
        }

        if ($Settings.alert -eq $true) {

            if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMTP Basic Authentication for tenant and all users is disabled' -sev Info
            } else {
                Write-StandardsAlert -message ($LogMessage -join '') -object @{TenantSMTPAuthDisabled = $CurrentInfo.SmtpClientAuthenticationDisabled; UsersWithSMTPAuthEnabled = $SMTPusers.Count } -tenant $tenant -standardName 'DisableBasicAuthSMTP' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $tenant -message ($LogMessage -join '') -sev Info
            }
        }

        if ($Settings.report -eq $true) {

            $CurrentValue = [PSCustomObject]@{
                SmtpClientAuthenticationDisabled = $CurrentInfo.SmtpClientAuthenticationDisabled
                UsersWithSmtpAuthEnabled         = $SMTPusers.PrimarySmtpAddress ? @($SMTPusers.PrimarySmtpAddress) : @()
            }
            $ExpectedValue = [PSCustomObject]@{
                SmtpClientAuthenticationDisabled = $true
                UsersWithSmtpAuthEnabled         = @()
            }

            Set-CIPPStandardsCompareField -FieldName 'standards.DisableBasicAuthSMTP' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant

            if ($CurrentInfo.SmtpClientAuthenticationDisabled -and $SMTPusers.Count -eq 0) {
                Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue $CurrentInfo.SmtpClientAuthenticationDisabled -StoreAs bool -Tenant $tenant
            } else {
                $Logs = $LogMessage | Select-Object @{n = 'Message'; e = { $_ } }
                Add-CIPPBPAField -FieldName 'DisableBasicAuthSMTP' -FieldValue $Logs -StoreAs json -Tenant $tenant
            }
        }
    }
}
