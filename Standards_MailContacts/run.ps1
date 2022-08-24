param($tenant)
$ConfigTable = Get-CippTable -tablename 'standards'
$Contacts = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.MailContacts
if (!$Contacts) {
    $Contacts = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.MailContacts
}

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