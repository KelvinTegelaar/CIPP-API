param($tenant)
$ConfigTable = Get-CippTable -tablename 'standards'
$Contacts = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.OutBoundSpamAlert
if (!$Contacts) {
    $Contacts = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.OutBoundSpamAlert
}

try {
    New-ExoRequest -tenantid $tenant -cmdlet "Set-HostedOutboundSpamFilterPolicy" -cmdparams @{ Identity = "Default"; NotifyOutboundSpam = $true; NotifyOutboundSpamRecipients = $Contacts.OutboundSpamContact } -useSystemMailbox $true
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Set outbound spam filter alert to $($Contacts.OutboundSpamContact)" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Could not set outbound spam contact to $($Contacts.OutboundSpamContact). $($_.exception.message)" -sev Error
}