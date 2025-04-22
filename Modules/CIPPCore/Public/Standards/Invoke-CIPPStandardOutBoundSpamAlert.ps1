function Invoke-CIPPStandardOutBoundSpamAlert {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OutBoundSpamAlert
    .SYNOPSIS
        (Label) Set Outbound Spam Alert e-mail
    .DESCRIPTION
        (Helptext) Set the Outbound Spam Alert e-mail address
        (DocsDescription) Sets the e-mail address to which outbound spam alerts are sent.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.OutBoundSpamAlert.OutboundSpamContact","label":"Outbound spam contact"}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-05-03
        POWERSHELLEQUIVALENT
            Set-HostedOutboundSpamFilterPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)

    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -useSystemMailbox $true

    if ($Settings.remediate -eq $true) {

        if ($CurrentInfo.NotifyOutboundSpam -ne $true -or $CurrentInfo.NotifyOutboundSpamRecipients -ne $settings.OutboundSpamContact) {
            $Contacts = $settings.OutboundSpamContact
            try {
                New-ExoRequest -tenantid $tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdParams @{ Identity = 'Default'; NotifyOutboundSpam = $true; NotifyOutboundSpamRecipients = $Contacts } -useSystemMailbox $true
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
            $Object = $CurrentInfo | Select-Object -Property NotifyOutboundSpamRecipients, NotifyOutboundSpam
            Write-StandardsAlert -message 'Outbound spam filter alert is not set' -object $Object -tenant $tenant -standardName 'OutBoundSpamAlert' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Outbound spam filter alert is not set' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'OutboundSpamAlert' -FieldValue $CurrentInfo.NotifyOutboundSpam -StoreAs bool -Tenant $tenant
        if ($CurrentInfo.NotifyOutboundSpam -ne $true -or $CurrentInfo.NotifyOutboundSpamRecipients -ne $settings.OutboundSpamContact) {
            $ValueField = $CurrentInfo | Select-Object -Property NotifyOutboundSpamRecipients, NotifyOutboundSpam
        } else {
            $ValueField = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.OutBoundSpamAlert' -FieldValue $ValueField -Tenant $tenant
    }
}
