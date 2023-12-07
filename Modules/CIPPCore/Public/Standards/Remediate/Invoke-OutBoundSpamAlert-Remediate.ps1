function Invoke-OutBoundSpamAlert-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Contacts = $settings.OutboundSpamContact

    try {
        New-ExoRequest -tenantid $tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdparams @{ Identity = 'Default'; NotifyOutboundSpam = $true; NotifyOutboundSpamRecipients = $Contacts.OutboundSpamContact } -useSystemMailbox $true
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Set outbound spam filter alert to $($Contacts.OutboundSpamContact)" -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set outbound spam contact to $($Contacts.OutboundSpamContact). $($_.exception.message)" -sev Error
    }
}
