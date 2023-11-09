param($tenant)
$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.ExcludedfileExt
if (!$Setting) {
    $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.ExcludedfileExt
}

try {
    $Exts = $Setting.ext -split ','
    $body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Added $($Setting.ext) to excluded synced files" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to add $($Setting.ext) to excluded synced files: $($_.exception.message)" -sev Error
}