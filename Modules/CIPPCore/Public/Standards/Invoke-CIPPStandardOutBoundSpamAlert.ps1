function Invoke-CIPPStandardOutBoundSpamAlert {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    OutBoundSpamAlert
    .CAT
    Exchange Standards
    .TAG
    "lowimpact"
    "CIS"
    .HELPTEXT
    Set the Outbound Spam Alert e-mail address
    .DOCSDESCRIPTION
    Sets the e-mail address to which outbound spam alerts are sent.
    .ADDEDCOMPONENT
    {"type":"input","name":"standards.OutBoundSpamAlert.OutboundSpamContact","label":"Outbound spam contact"}
    .LABEL
    Set Outbound Spam Alert e-mail
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Set-HostedOutboundSpamFilterPolicy
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Set the Outbound Spam Alert e-mail address
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
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




