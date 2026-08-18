function Invoke-CIPPStandardEnableAppConsentRequests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableAppConsentRequests
    .SYNOPSIS
        (Label) Enable App consent admin requests
    .DESCRIPTION
        (Helptext) Enables App consent admin requests for the tenant via the GA role. Optionally adds specific users (matched by display name) as reviewers. Does not overwrite existing reviewer settings
        (DocsDescription) Enables the ability for users to request admin consent for applications. Reviewers can be directory roles and/or specific users matched by display name, e.g. a central MSP support account that exists as a guest in each tenant, so each consent request generates a notification to a monitored mailbox. Should be used in conjunction with the "Require admin consent for applications" standards
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 7.0.0 (5.1.5.2)"
            "CISA (MS.AAD.9.1v1)"
            "EIDSCA.CP04"
            "EIDSCA.CR01"
            "EIDSCA.CR02"
            "EIDSCA.CR03"
            "EIDSCA.CR04"
            "Essential 8 (1507)"
            "NIST CSF 2.0 (PR.AA-05)"
        APPLIESTOTEST
            "CIS_5_1_5_2"
            "EIDSCACP04"
            "EIDSCACR01"
            "EIDSCACR02"
            "EIDSCACR03"
            "EIDSCACR04"
            "ZTNA21809"
            "ZTNA21869"
        EXECUTIVETEXT
            Establishes a formal approval process where employees can request access to business applications that require administrative review. This balances security with productivity by allowing controlled access to necessary tools while preventing unauthorized application installations.
        ADDEDCOMPONENT
            {"type":"AdminRolesMultiSelect","label":"App Consent Reviewer Roles","name":"standards.EnableAppConsentRequests.ReviewerRoles"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"label":"Optional: reviewer users (display names of existing users or guests)","name":"standards.EnableAppConsentRequests.ReviewerUsers"}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-11-27
        POWERSHELLEQUIVALENT
            Update-MgPolicyAdminConsentRequestPolicy
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableAppConsentRequests state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
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

            # Users from standards table, matched on display name so the reviewer account
            # can be created any way (invited guest, B2B, manual) regardless of which mail
            # attribute ended up populated
            $ReviewerUserNames = @(($Settings.ReviewerUsers.value ?? $Settings.ReviewerUsers) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $ReviewerUsers = [System.Collections.Generic.List[object]]::new()
            foreach ($Name in $ReviewerUserNames) {
                $UserFilter = [System.Uri]::EscapeDataString("displayName eq '$($Name -replace "'", "''")'")
                $MatchedUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,displayName&`$filter=$UserFilter" -tenantid $Tenant)
                if ($MatchedUsers.Count -eq 0) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "EnableAppConsentRequests: No user found with display name '$Name', not added as reviewer" -sev Warning
                    continue
                }
                foreach ($User in $MatchedUsers) { $ReviewerUsers.Add($User) }
            }

            $NewReviewers = [System.Collections.Generic.List[object]]::new()
            foreach ($Role in $RolesToAdd) {
                $NewReviewers.Add(@{
                        query     = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$Role'"
                        queryType = 'MicrosoftGraph'
                        queryRoot = 'null'
                    })
            }
            foreach ($User in $ReviewerUsers) {
                $NewReviewers.Add(@{
                        query     = "/users/$($User.id)"
                        queryType = 'MicrosoftGraph'
                        queryRoot = 'null'
                    })
            }

            # Add existing reviewers, skipping any that the configured roles/users already cover
            $IdsToAdd = @($RolesToAdd) + @($ReviewerUsers | ForEach-Object { $_.id })
            $Reviewers = [System.Collections.Generic.List[object]]::new()
            foreach ($Reviewer in $CurrentInfo.reviewers) {
                $Found = $false
                foreach ($Id in $IdsToAdd) {
                    if ($Reviewer.query -match $Id -or $Reviewers.query -contains $Reviewer.query) {
                        $Found = $true
                    }
                }
                if (!$Found) {
                    $Reviewers.add($Reviewer)
                }
            }

            # Add new reviewer roles and users
            foreach ($NewReviewer in $NewReviewers) {
                $Reviewers.add($NewReviewer)
            }

            # Update reviewer list
            $CurrentInfo.reviewers = @($Reviewers)
            $body = (ConvertTo-Json -Compress -Depth 10 -InputObject $CurrentInfo)

            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -Type put -Body $body -ContentType 'application/json'
            $UserLogSuffix = if ($ReviewerUsers.Count -gt 0) { " and the following users: $(@($ReviewerUsers | ForEach-Object { $_.displayName }) -join ', ')" } else { '' }
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled App consent admin requests for the following roles: $RoleNames$UserLogSuffix" -sev Info

        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable App consent admin requests. Error: $ErrorMessage" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.isEnabled -eq 'true') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'App consent admin requests are enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'App consent admin requests are disabled' -object $CurrentInfo -tenant $tenant -standardName 'EnableAppConsentRequests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'App consent admin requests are disabled' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        # Set default if no roles are selected, matches remediation logic
        $RolesToAdd = $Settings.ReviewerRoles.value
        if (!$RolesToAdd -or $RolesToAdd.Count -eq 0) {
            $RolesToAdd = @('62e90394-69f5-4237-9190-012177145e10')
        }
        $ReviewerUserNames = @(($Settings.ReviewerUsers.value ?? $Settings.ReviewerUsers) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $CurrentValue = [PSCustomObject]@{
            EnableAppConsentRequests = [bool]$CurrentInfo.isEnabled
            ReviewerCount            = $CurrentInfo.reviewers.count
        }
        $ExpectedValue = [PSCustomObject]@{
            EnableAppConsentRequests = $true
            ReviewerCount            = $RolesToAdd.Count + $ReviewerUserNames.Count
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableAppConsentRequests' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnableAppConsentAdminRequests' -FieldValue $CurrentInfo.isEnabled -StoreAs bool -Tenant $tenant
    }
}
