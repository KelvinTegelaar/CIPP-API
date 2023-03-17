param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.spoofwarn
$status = if ($Setting.enable -and $Setting.disable) {
    Write-LogMessage -API "Standards" -tenant $tenant -message "You cannot both enable and disable the Spoof Warnings setting" -sev Error
    Exit
}
elseif ($setting.enable) { $true } else { $false }
try {
    New-ExoRequest -tenantid $Tenant -cmdlet "Set-ExternalInOutlook" -cmdParams @{ Enabled = $status; }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Spoofing warnings set to $status." -sev Info

}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Could not set spoofing warnings to $status. Error: $($_.exception.message)" -sev Error
}