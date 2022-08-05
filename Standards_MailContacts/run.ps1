param($tenant)
if ((Test-Path ".\Cache_Standards\$($Tenant).Standards.json")) {
    $Contacts = (Get-Content ".\Cache_Standards\$($Tenant).Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.MailContacts
}

if (!$contacts) { $Contacts = (Get-Content ".\Cache_Standards\AllTenants.Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.MailContacts }

try {
    $TenantID = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/organization" -tenantid $tenant)
    $Body = [pscustomobject]@{}
    switch ($Contacts) {
        { $Contacts.marketingcontact.mail } { $body | Add-Member -NotePropertyName marketingNotificationEmails -NotePropertyValue @($Contacts.marketingcontact.mail) }
        { $Contacts.SecurityContact.Mail } { $body | Add-Member -NotePropertyName securityComplianceNotificationMails -NotePropertyValue @($Contacts.SecurityContact.Mail) }
        { $Contacts.TechContact.Mail } { $body | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @($Contacts.TechContact.Mail) }
        { $Contacts.GeneralContact.Mail } { $body | Add-Member -NotePropertyName privacyProfile -NotePropertyValue @{contactEmail = $Contacts.GeneralContact.Mail } }
    }
    Write-Host  (ConvertTo-Json -InputObject $body)
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/organization/$($TenantID.id)" -Type patch -Body (ConvertTo-Json -InputObject $body) -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Contact email's set." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set contact emails: $($_.exception.message)" -sev Error
}