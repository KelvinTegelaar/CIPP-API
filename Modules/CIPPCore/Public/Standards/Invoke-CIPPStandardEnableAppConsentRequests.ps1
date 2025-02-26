function Invoke-CIPPStandardEnableAppConsentRequests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableAppConsentRequests
    .SYNOPSIS
        (Label) Enable App consent admin requests
    .DESCRIPTION
        (Helptext) Enables App consent admin requests for the tenant via the GA role. Does not overwrite existing reviewer settings
        (DocsDescription) Enables the ability for users to request admin consent for applications. Should be used in conjunction with the "Require admin consent for applications" standards
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"AdminRolesMultiSelect","label":"App Consent Reviewer Roles","name":"standards.EnableAppConsentRequests.ReviewerRoles"}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-11-27
        POWERSHELLEQUIVALENT
            Update-MgPolicyAdminConsentRequestPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableAppConsentRequests'

    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        try {
            # Get current state

            # Change state to enabled with default settings
            $CurrentInfo.isEnabled = 'true'
            $CurrentInfo.notifyReviewers = 'true'
            $CurrentInfo.remindersEnabled = 'true'
            $CurrentInfo.requestDurationInDays = 30

            # Roles from standards table
            $RolesToAdd = $Settings.ReviewerRoles.value
            $RoleNames = $Settings.ReviewerRoles.label -join ', '

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
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable App consent admin requests. Error: $ErrorMessage" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isEnabled -eq 'true') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'App consent admin requests are enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'App consent admin requests are disabled' -sev Alert
        }
    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'EnableAppConsentAdminRequests' -FieldValue $CurrentInfo.isEnabled -StoreAs bool -Tenant $tenant
    }
}
