function Invoke-CIPPStandardOutBoundSpamAlert {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -useSystemMailbox $true

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.NotifyOutboundSpam -ne $true -or $CurrentInfo.NotifyOutboundSpamRecipients -ne $settings.OutboundSpamContact) {
            $Contacts = $settings.OutboundSpamContact
            try {
                New-ExoRequest -tenantid $tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdparams @{ Identity = 'Default'; NotifyOutboundSpam = $true; NotifyOutboundSpamRecipients = $Contacts } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set outbound spam filter alert to $($Contacts)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set outbound spam contact to $($Contacts). $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Outbound spam filter alert is already set to $($CurrentInfo.NotifyOutboundSpamRecipients)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.NotifyOutboundSpam -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Outbound spam filter alert is set to $($CurrentInfo.NotifyOutboundSpamRecipients)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Outbound spam filter alert is not set' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'OutboundSpamAlert' -FieldValue $CurrentInfo.NotifyOutboundSpam -StoreAs bool -Tenant $tenant
    }
}
