param($tenant)

try {
    #$Alerts = Get-Content ".\Cache_Scheduler\$tenant.alert.json" | ConvertFrom-Json
    Write-Host "GENERATING ALERT!!!!"
    #Write-Host $Alerts
}
catch {
    Log-request -API "Scheduler" -tenant $tenant -message "Failed to get alerts for $($tenant) Error: $($_.exception.message)" -sev Error
}