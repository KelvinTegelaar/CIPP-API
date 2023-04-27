param($tenant)
try {
    $PreviousSetting = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -tenantid $Tenant
    $previoussetting.localadminpassword.isEnabled = $true 
    $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -Type PUT -Body $newBody -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "LAPS has been enabled." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set LAPS: $($_.exception.message)" -sev Error
}