param($tenant)

try {
    $CurrentState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/settings" -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'
    if (!$CurrentState) {
        #if no current configuration is found, we set it to the default template supplied by MS.
        $CurrentState = '{"id":"","displayName":"Group.Unified","templateId":"62375ab9-6b52-47ed-826b-58e47e0e304b","values":[{"name":"NewUnifiedGroupWritebackDefault","value":"true"},{"name":"EnableMIPLabels","value":"false"},{"name":"CustomBlockedWordsList","value":""},{"name":"EnableMSStandardBlockedWords","value":"false"},{"name":"ClassificationDescriptions","value":""},{"name":"DefaultClassification","value":""},{"name":"PrefixSuffixNamingRequirement","value":""},{"name":"AllowGuestsToBeGroupOwner","value":"false"},{"name":"AllowGuestsToAccessGroups","value":"true"},{"name":"GuestUsageGuidelinesUrl","value":""},{"name":"GroupCreationAllowedGroupId","value":""},{"name":"AllowToAddGuests","value":"true"},{"name":"UsageGuidelinesUrl","value":""},{"name":"ClassificationList","value":""},{"name":"EnableGroupCreation","value":"true"}]}'
        (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -Type POST -Body $CurrentState  -ContentType "application/json")
        $CurrentState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/settings" -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'
    }
    ($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value = "false"
    $body = "{values : $($CurrentState.values | ConvertTo-Json -Compress)}"
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -Type patch -Body $body -ContentType "application/json")
    Write-LogMessage -API "Standards" -tenant $tenant -message "Standards API: Disabled users from creating M365 Groups." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable users from creating M365 Groups: $($_.exception.message)" -sev "Error"
}
