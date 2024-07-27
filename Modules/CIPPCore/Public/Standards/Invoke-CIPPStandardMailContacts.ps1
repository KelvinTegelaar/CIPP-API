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
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"input","name":"standards.MailContacts.GeneralContact","label":"General Contact"}
            {"type":"input","name":"standards.MailContacts.SecurityContact","label":"Security Contact"}
            {"type":"input","name":"standards.MailContacts.MarketingContact","label":"Marketing Contact"}
            {"type":"input","name":"standards.MailContacts.TechContact","label":"Technical Contact"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-MsolCompanyContactInformation
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $TenantID = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/organization' -tenantid $tenant)
    $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -tenantid $Tenant
    $contacts = $settings
    $TechAndSecurityContacts = @($Contacts.SecurityContact, $Contacts.TechContact)

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.marketingNotificationEmails -eq $Contacts.MarketingContact -and `
            ($CurrentInfo.securityComplianceNotificationMails -in $TechAndSecurityContacts -or
                $CurrentInfo.technicalNotificationMails -in $TechAndSecurityContacts) -and `
                $CurrentInfo.privacyProfile.contactEmail -eq $Contacts.GeneralContact) {
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
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Marketing contact email is not set to $($Contacts.MarketingContact)" -sev Alert
        }
        if ($CurrentInfo.securityComplianceNotificationMails -eq $Contacts.SecurityContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Security contact email is set to $($Contacts.SecurityContact)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Security contact email is not set to $($Contacts.SecurityContact)" -sev Alert
        }
        if ($CurrentInfo.technicalNotificationMails -eq $Contacts.TechContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Technical contact email is set to $($Contacts.TechContact)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Technical contact email is not set to $($Contacts.TechContact)" -sev Alert
        }
        if ($CurrentInfo.privacyProfile.contactEmail -eq $Contacts.GeneralContact) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "General contact email is set to $($Contacts.GeneralContact)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "General contact email is not set to $($Contacts.GeneralContact)" -sev Alert
        }

    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'MailContacts' -FieldValue $CurrentInfo -StoreAs json -Tenant $tenant
    }
}
