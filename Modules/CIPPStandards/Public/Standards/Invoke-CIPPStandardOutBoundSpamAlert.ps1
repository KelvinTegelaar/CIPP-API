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
            "CIS M365 5.0 (2.1.6)"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.OutBoundSpamAlert.OutboundSpamContact","label":"Outbound spam contact"}
            {"type":"switch","name":"standards.OutBoundSpamAlert.BccSuspiciousOutboundMail","label":"BCC suspicious outbound mail to a mailbox"}
            {"type":"textField","name":"standards.OutBoundSpamAlert.BccSuspiciousOutboundContact","label":"BCC recipient for suspicious outbound mail"}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-05-03
        POWERSHELLEQUIVALENT
            Set-HostedOutboundSpamFilterPolicy
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'OutBoundSpamAlert' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -cmdParams @{ Identity = 'Default' } -useSystemMailbox $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the OutBoundSpamAlert state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $Contacts = $Settings.OutboundSpamContact
    # BccSuspiciousOutboundMail is opt-in: only graded/remediated when the operator enables the
    # toggle. CIS 2.1.6 requires both the flag AND a recipient, so a compliant state needs the
    # additional recipients too when a BCC contact is supplied.
    $ManageBcc = $Settings.BccSuspiciousOutboundMail -eq $true
    $BccContacts = $Settings.BccSuspiciousOutboundContact

    $CurrentNotifyRecipients = @($CurrentInfo.NotifyOutboundSpamRecipients) -join ', '
    $NotifyIsCorrect = ($CurrentInfo.NotifyOutboundSpam -eq $true) -and ($CurrentNotifyRecipients -eq "$Contacts")

    $CurrentBccRecipients = @($CurrentInfo.BccSuspiciousOutboundAdditionalRecipients) -join ', '
    if (-not $ManageBcc) {
        $BccIsCorrect = $true
    } elseif ([string]::IsNullOrWhiteSpace($BccContacts)) {
        $BccIsCorrect = $CurrentInfo.BccSuspiciousOutboundMail -eq $true
    } else {
        $BccIsCorrect = ($CurrentInfo.BccSuspiciousOutboundMail -eq $true) -and ($CurrentBccRecipients -eq "$BccContacts")
    }
    $StateIsCorrect = $NotifyIsCorrect -and $BccIsCorrect

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Outbound spam filter alert is already set to $($CurrentInfo.NotifyOutboundSpamRecipients)" -sev Info
        } else {
            $cmdParams = @{
                Identity                     = 'Default'
                NotifyOutboundSpam           = $true
                NotifyOutboundSpamRecipients = $Contacts
            }
            if ($ManageBcc) {
                $cmdParams.BccSuspiciousOutboundMail = $true
                if (-not [string]::IsNullOrWhiteSpace($BccContacts)) {
                    $cmdParams.BccSuspiciousOutboundAdditionalRecipients = $BccContacts
                }
            }
            try {
                New-ExoRequest -tenantid $tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdParams $cmdParams -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set outbound spam filter alert to $($Contacts)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not set outbound spam contact to $($Contacts). $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Outbound spam filter alert is set to $($CurrentInfo.NotifyOutboundSpamRecipients)" -sev Info
        } else {
            $Object = $CurrentInfo | Select-Object -Property NotifyOutboundSpam, NotifyOutboundSpamRecipients, BccSuspiciousOutboundMail, BccSuspiciousOutboundAdditionalRecipients
            Write-StandardsAlert -message 'Outbound spam filter alert is not set' -object $Object -tenant $tenant -standardName 'OutBoundSpamAlert' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Outbound spam filter alert is not set' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'OutboundSpamAlert' -FieldValue $CurrentInfo.NotifyOutboundSpam -StoreAs bool -Tenant $tenant
        $CurrentValue = @{
            NotifyOutboundSpam           = $CurrentInfo.NotifyOutboundSpam
            NotifyOutboundSpamRecipients = $CurrentNotifyRecipients
        }
        $ExpectedValue = @{
            NotifyOutboundSpam           = $true
            NotifyOutboundSpamRecipients = $Contacts
        }
        if ($ManageBcc) {
            $CurrentValue.BccSuspiciousOutboundMail = $CurrentInfo.BccSuspiciousOutboundMail
            $CurrentValue.BccSuspiciousOutboundAdditionalRecipients = $CurrentBccRecipients
            $ExpectedValue.BccSuspiciousOutboundMail = $true
            $ExpectedValue.BccSuspiciousOutboundAdditionalRecipients = $BccContacts
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.OutBoundSpamAlert' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
    }
}
