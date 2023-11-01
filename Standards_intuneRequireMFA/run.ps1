param($tenant)
try {
    $PreviousSetting = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -tenantid $Tenant
    $PreviousSetting.multiFactorAuthConfiguration = '1'
    $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -Type PUT -Body $NewBody -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Set required to use MFA when joining Intune Devices" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set require to use MFA when joining Intune Devices: $($_.exception.message)" -sev Error
}