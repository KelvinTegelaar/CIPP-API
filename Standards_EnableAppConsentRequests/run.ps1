param($tenant)

try {
    # Get current state
    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $Tenant
    
    # Change state to enabled with default settings
    $CurrentInfo.isEnabled = 'true'
    $CurrentInfo.notifyReviewers = 'true'
    $CurrentInfo.remindersEnabled = 'true'
    $CurrentInfo.requestDurationInDays = 30

    # Get Global Admin role ID TODO: change to be able to chose role
    $Role = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions?`$filter=(displayName eq 'Global Administrator')&`$select=displayName,id" -tenantid $Tenant
    $RoleReviewers = @(@{
            query     = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq `'$($Role.id)`'"
            queryType = 'MicrosoftGraph'
            queryRoot = 'null'
        })
    # Set reviewers to Global Admins if not already set, this avoids overwriting existing reviewers and duplication of reviewers objects
    $CurrentInfo.reviewers = if ($CurrentInfo.reviewers.query -notlike "*$($Role.id)*") {
        $RoleReviewers
    }
    $body = (ConvertTo-Json -Depth 10 -InputObject $CurrentInfo)
    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -Type put -Body $body -ContentType 'application/json')


    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled App consent admin requests' -sev Info
    
} catch {
    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable App consent admin requests. Error: $($_.exception.message)" -sev Error
}
