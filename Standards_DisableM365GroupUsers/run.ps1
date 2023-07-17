param($tenant)

try {
    $CurrentState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/settings" -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'
    ($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value = "false"
    $body = "{values : $($CurrentState.values | ConvertTo-Json -Compress)}"
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -Type patch -Body $body -ContentType "application/json")
    Write-LogMessage -API "Standards" -tenant $tenant -message "Standards API: Disabled users from creating Security Groups." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable users from creating Security Groups: $($_.exception.message)" -sev "Error"
}
