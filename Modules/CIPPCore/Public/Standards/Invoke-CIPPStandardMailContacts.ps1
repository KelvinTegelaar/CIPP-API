function Invoke-CIPPStandardMailContacts {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $TenantID = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/organization' -tenantid $tenant)

    If ($Settings.remediate) {
    
        $contacts = $settings
        try {
            $Body = [pscustomobject]@{}
            switch ($Contacts) {
                { $Contacts.MarketingContact } { $body | Add-Member -NotePropertyName marketingNotificationEmails -NotePropertyValue @($Contacts.MarketingContact) }
                { $Contacts.SecurityContact } { $body | Add-Member -NotePropertyName securityComplianceNotificationMails -NotePropertyValue @($Contacts.SecurityContact) }
                { $Contacts.TechContact } { $body | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @($Contacts.TechContact) }
                { $Contacts.GeneralContact } { $body | Add-Member -NotePropertyName privacyProfile -NotePropertyValue @{contactEmail = $Contacts.GeneralContact } }
            }
            Write-Host (ConvertTo-Json -InputObject $body)
            New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -asApp $true -Type patch -Body (ConvertTo-Json -InputObject $body) -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Contact email's set." -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set contact emails: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -tenantid $Tenant
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
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'MailContacts' -FieldValue $CurrentInfo -StoreAs json -Tenant $tenant
    }
}
