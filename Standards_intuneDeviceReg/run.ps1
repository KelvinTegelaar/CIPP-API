param($tenant)
try {
    $ConfigTable = Get-CippTable -tablename 'standards'
    $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.intuneDeviceReg
    if (!$Setting) {
        $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.intuneDeviceReg
    }
    $PreviousSetting = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -tenantid $Tenant
    $PreviousSetting.userDeviceQuota = $Setting.max
    $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -Type PUT -Body $NewBody -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Set user device quota to $($setting.max)" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set user device quota to $($setting.max) : $($_.exception.message)" -sev Error
}