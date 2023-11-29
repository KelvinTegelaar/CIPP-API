param($tenant)

try {

    $ConfigTable = Get-CippTable -tablename 'standards'
    $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.EnableAppConsentRequests
    if (!$Setting) {
        $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.EnableAppConsentRequests
    }

    # Get current state
    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $Tenant

    # Change state to enabled with default settings
    $CurrentInfo.isEnabled = 'true'
    $CurrentInfo.notifyReviewers = 'true'
    $CurrentInfo.remindersEnabled = 'true'
    $CurrentInfo.requestDurationInDays = 30

    # Roles from standards table
    $RolesToAdd = $Setting.ReviewerRoles.value
    $RoleNames = $Setting.ReviewerRoles.label -join ', '

    # Set default if no roles are selected
    if (!$RolesToAdd) {
        $RolesToAdd = @('62e90394-69f5-4237-9190-012177145e10')
        $RoleNames = '(Default) Global Administrator'
    }

    $NewReviewers = foreach ($Role in $RolesToAdd) {
        @{
            query     = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$Role'"
            queryType = 'MicrosoftGraph'
            queryRoot = 'null'
        }
    }

    # Add existing reviewers
    $Reviewers = [System.Collections.Generic.List[object]]::new()
    foreach ($Reviewer in $CurrentInfo.reviewers) {
        $RoleFound = $false
        foreach ($Role in $RolesToAdd) {
            if ($Reviewer.query -match $Role -or $Reviewers.query -contains $Reviewer.query) {
                $RoleFound = $true
            }
        }
        if (!$RoleFound) {
            $Reviewers.add($Reviewer)
        }
    }

    # Add new reviewer roles
    foreach ($NewReviewer in $NewReviewers) {
        $Reviewers.add($NewReviewer)
    }

    # Update reviewer list
    $CurrentInfo.reviewers = @($Reviewers)
    $body = (ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo)

    New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -Type put -Body $body -ContentType 'application/json'
    Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled App consent admin requests for the following roles: $RoleNames" -sev Info

} catch {
    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable App consent admin requests. Error: $($_.exception.message)" -sev Error
}
