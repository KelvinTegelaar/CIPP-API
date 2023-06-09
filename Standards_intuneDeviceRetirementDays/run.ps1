param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.DeviceInactivityBeforeRetirementInDays
if (!$Setting) {
    $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.DeviceInactivityBeforeRetirementInDays
}

try {

    $body = @{ DeviceInactivityBeforeRetirementInDays = $Setting.days } | ConvertTo-Json

    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings" -Type PATCH -Body $body -ContentType "application/json")

    Write-LogMessage  -API "Standards" -tenant $tenant -message "Enabled DeviceInactivityBeforeRetirementInDays." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $($_.exception.message)" -sev Error
}