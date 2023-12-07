function Invoke-MailContacts-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $contacts = $settings

    try {
        $TenantID = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/organization' -tenantid $tenant)
        $Body = [pscustomobject]@{}
        switch ($Contacts) {
            { $Contacts.MarketingContact } { $body | Add-Member -NotePropertyName marketingNotificationEmails -NotePropertyValue @($Contacts.MarketingContact) }
            { $Contacts.SecurityContact } { $body | Add-Member -NotePropertyName securityComplianceNotificationMails -NotePropertyValue @($Contacts.SecurityContact) }
            { $Contacts.TechContact } { $body | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @($Contacts.TechContact) }
            { $Contacts.GeneralContact } { $body | Add-Member -NotePropertyName privacyProfile -NotePropertyValue @{contactEmail = $Contacts.GeneralContact } }
        }
        Write-Host (ConvertTo-Json -InputObject $body)
        New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -Type patch -Body (ConvertTo-Json -InputObject $body) -ContentType 'application/json'
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Contact email's set." -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set contact emails: $($_.exception.message)" -sev Error
    }
}
