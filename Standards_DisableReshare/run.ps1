param($tenant)

try {
    #Seems like MS made a mistake here, notified them of the flipped boolean. will change when they fix this.
    $body = '{"isResharingByExternalUsersEnabled": "True"}'
    $Request = New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Write-Host "Here's Johnny"
    Write-Host ($Request | ConvertTo-Json)
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Disabled guests from resharing files" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable guests from resharing files: $($_.exception.message)" -sev Error
}