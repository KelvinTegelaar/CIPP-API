function Invoke-CIPPStandardMailContacts {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MailContacts
    .SYNOPSIS
        (Label) Set contact e-mails
    .DESCRIPTION
        (Helptext) Defines the email address to receive general updates and information related to M365 subscriptions. Leave a contact field blank if you do not want to update the contact information.
        (DocsDescription) Defines the email address to receive general updates and information related to M365 subscriptions. Leave a contact field blank if you do not want to update the contact information.
    .NOTES
        CAT
            Global Standards
        TAG
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.MailContacts.GeneralContact","label":"General Contact","required":false}
            {"type":"textField","name":"standards.MailContacts.SecurityContact","label":"Security Contact","required":false}
            {"type":"textField","name":"standards.MailContacts.MarketingContact","label":"Marketing Contact","required":false}
            {"type":"textField","name":"standards.MailContacts.TechContact","label":"Technical Contact","required":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-03-13
        POWERSHELLEQUIVALENT
            Set-MsolCompanyContactInformation
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'MailContacts'

    $TenantID = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/organization' -tenantid $tenant)
    $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -tenantid $Tenant
    $contacts = $settings
    $TechAndSecurityContacts = @($Contacts.SecurityContact, $Contacts.TechContact)

    if ($Settings.remediate -eq $true) {
        $state = $CurrentInfo.marketingNotificationEmails -eq $Contacts.MarketingContact -and `
        ($CurrentInfo.securityComplianceNotificationMails -in $TechAndSecurityContacts -or
            $CurrentInfo.technicalNotificationMails -in $TechAndSecurityContacts) -and `
            $CurrentInfo.privacyProfile.contactEmail -eq $Contacts.GeneralContact
        if ($state) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Contact emails are already set.' -sev Info
        } else {
            try {
                $Body = [pscustomobject]@{}
                switch ($Contacts) {
                    { $Contacts.MarketingContact } { $body | Add-Member -NotePropertyName marketingNotificationEmails -NotePropertyValue @($Contacts.MarketingContact) }
                    { $Contacts.SecurityContact } { $body | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @($Contacts.SecurityContact) }
                    { $Contacts.TechContact } { $body | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @($Contacts.TechContact) -ErrorAction SilentlyContinue }
                    { $Contacts.GeneralContact } { $body | Add-Member -NotePropertyName privacyProfile -NotePropertyValue @{contactEmail = $Contacts.GeneralContact } }
                }
                Write-Host (ConvertTo-Json -InputObject $body)
                New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/v1.0/organization/$($TenantID.id)" -asApp $true -Type patch -Body (ConvertTo-Json -InputObject $body) -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Contact emails set.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set contact emails: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.marketingNotificationEmails -eq $Contacts.MarketingContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Marketing contact email is set to $($Contacts.MarketingContact)" -sev Info
        } else {
            $Object = $CurrentInfo | Select-Object marketingNotificationEmails
            Write-StandardsAlert -message "Marketing contact email is not set to $($Contacts.MarketingContact)" -object $Object -tenant $tenant -standardName 'MailContacts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Marketing contact email is not set to $($Contacts.MarketingContact)" -sev Info
        }
        if (!$Contacts.SecurityContact -or $CurrentInfo.technicalNotificationMails -contains $Contacts.SecurityContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Security contact email is set to $($Contacts.SecurityContact)" -sev Info
        } else {
            $Object = $CurrentInfo | Select-Object technicalNotificationMails
            Write-StandardsAlert -message "Security contact email is not set to $($Contacts.SecurityContact)" -object $Object -tenant $tenant -standardName 'MailContacts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Security contact email is not set to $($Contacts.SecurityContact)" -sev Info
        }
        if (!$Contacts.TechContact -or $CurrentInfo.technicalNotificationMails -contains $Contacts.TechContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Technical contact email is set to $($Contacts.TechContact)" -sev Info
        } else {
            $Object = $CurrentInfo | Select-Object technicalNotificationMails
            Write-StandardsAlert -message "Technical contact email is not set to $($Contacts.TechContact)" -object $Object -tenant $tenant -standardName 'MailContacts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Technical contact email is not set to $($Contacts.TechContact)" -sev Info
        }
        if ($CurrentInfo.privacyProfile.contactEmail -eq $Contacts.GeneralContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "General contact email is set to $($Contacts.GeneralContact)" -sev Info
        } else {
            $Object = $CurrentInfo | Select-Object privacyProfile
            Write-StandardsAlert -message "General contact email is not set to $($Contacts.GeneralContact)" -object $Object -tenant $tenant -standardName 'MailContacts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "General contact email is not set to $($Contacts.GeneralContact)" -sev Info
        }

    }
    if ($Settings.report -eq $true) {
        $ReportState = $state ? $true : ($CurrentInfo | Select-Object marketingNotificationEmails, technicalNotificationMails, privacyProfile)
        Set-CIPPStandardsCompareField -FieldName 'standards.MailContacts' -FieldValue $ReportState -Tenant $tenant
        Add-CIPPBPAField -FieldName 'MailContacts' -FieldValue $CurrentInfo -StoreAs json -Tenant $tenant
    }
}
