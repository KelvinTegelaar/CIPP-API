function Invoke-CIPPStandardDisableM365GroupUsers {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableM365GroupUsers
    .SYNOPSIS
        (Label) Disable M365 Group creation by users
    .DESCRIPTION
        (Helptext) Restricts M365 group creation to certain admin roles. This disables the ability to create Teams, SharePoint sites, Planner, etc. Optionally allows members of a specific security group to keep creating groups (GroupCreationAllowedGroupId).
        (DocsDescription) Users by default are allowed to create M365 groups. This restricts M365 group creation to certain admin roles. This disables the ability to create Teams, SharePoint sites, Planner, etc. Optionally, a security group can be named whose members remain allowed to create groups; the group is resolved by display name in each tenant and can be created automatically when it does not exist. When no group is named, the existing GroupCreationAllowedGroupId value in the tenant is left untouched.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CISA (MS.AAD.21.1v1)"
            "ZTNA21868"
        EXECUTIVETEXT
            Restricts the creation of Microsoft 365 groups, Teams, and SharePoint sites to authorized administrators, preventing uncontrolled proliferation of collaboration spaces. This ensures proper governance, naming conventions, and resource management while maintaining oversight of all collaborative environments. An approved group of designated users can optionally retain the ability to create groups.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DisableM365GroupUsers.AllowedGroupName","label":"Optional: name of the group whose members may still create M365 groups","required":false}
            {"type":"switch","name":"standards.DisableM365GroupUsers.CreateGroup","label":"Create the allowed group if it does not exist","required":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-07-17
        POWERSHELLEQUIVALENT
            Update-MgBetaDirectorySetting
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableM365GroupUsers' -TenantFilter $Tenant -Preset SharePoint

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $tenant) |
            Where-Object -Property displayname -EQ 'Group.unified'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableM365GroupUsers state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Optional: a group whose members remain allowed to create M365 groups
    # (GroupCreationAllowedGroupId). Resolved by display name per tenant, since group ids
    # differ between tenants. When no name is configured the setting is left untouched,
    # which keeps existing deployments unchanged.
    $AllowedGroupName = [string]$Settings.AllowedGroupName
    $DesiredGroupId = $null
    if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName)) {
        try {
            $GroupFilter = [System.Uri]::EscapeDataString("displayName eq '$($AllowedGroupName -replace "'", "''")'")
            $AllowedGroup = @(New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups?`$filter=$GroupFilter&`$select=id,displayName" -tenantid $Tenant)
            if ($AllowedGroup.Count -gt 1) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Multiple groups named '$AllowedGroupName' found, using the first match ($($AllowedGroup[0].id))." -sev Warning
            }
            $DesiredGroupId = $AllowedGroup | Select-Object -First 1 -ExpandProperty id
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not resolve the allowed group '$AllowedGroupName': $ErrorMessage" -sev Error
        }
    }

    $CurrentEnableGroupCreation = ($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value
    $CurrentAllowedGroupId = ($CurrentState.values | Where-Object { $_.name -eq 'GroupCreationAllowedGroupId' }).value
    $CreationDisabled = $CurrentEnableGroupCreation -eq 'false'
    # Only enforce the allowed group when one is configured; a configured name that cannot be
    # resolved (and is not set for creation) counts as non-compliant so it surfaces in alerts
    $AllowedGroupCorrect = [string]::IsNullOrWhiteSpace($AllowedGroupName) -or ($DesiredGroupId -and $CurrentAllowedGroupId -eq $DesiredGroupId)
    $StateIsCorrect = $CreationDisabled -and $AllowedGroupCorrect

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already disabled from creating M365 Groups.' -sev Info
        } else {
            try {
                # Create the allowed group when requested and it does not exist yet
                if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName) -and -not $DesiredGroupId -and $Settings.CreateGroup -eq $true) {
                    $GroupUsername = ($AllowedGroupName -replace '[^a-zA-Z0-9]', '')
                    if ($GroupUsername.Length -gt 64) { $GroupUsername = $GroupUsername.Substring(0, 64) }
                    $GroupObject = @{
                        groupType       = 'generic'
                        displayName     = $AllowedGroupName
                        username        = $GroupUsername
                        securityEnabled = $true
                    }
                    $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $Tenant -APIName 'Standards'
                    $DesiredGroupId = $NewGroup.GroupId
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created group '$AllowedGroupName' ($DesiredGroupId) for allowed M365 group creation." -sev Info
                }
                if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName) -and -not $DesiredGroupId) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "The allowed group '$AllowedGroupName' does not exist in the tenant and 'Create the allowed group' is not enabled. Group creation will be disabled without an allowed group." -sev Warning
                }

                if (!$CurrentState) {
                    # If no current configuration is found, we set it to the default template supplied by MS.
                    $CurrentState = '{"id":"","displayName":"Group.Unified","templateId":"62375ab9-6b52-47ed-826b-58e47e0e304b","values":[{"name":"NewUnifiedGroupWritebackDefault","value":"true"},{"name":"EnableMIPLabels","value":"false"},{"name":"CustomBlockedWordsList","value":""},{"name":"EnableMSStandardBlockedWords","value":"false"},{"name":"ClassificationDescriptions","value":""},{"name":"DefaultClassification","value":""},{"name":"PrefixSuffixNamingRequirement","value":""},{"name":"AllowGuestsToBeGroupOwner","value":"false"},{"name":"AllowGuestsToAccessGroups","value":"true"},{"name":"GuestUsageGuidelinesUrl","value":""},{"name":"GroupCreationAllowedGroupId","value":""},{"name":"AllowToAddGuests","value":"true"},{"name":"UsageGuidelinesUrl","value":""},{"name":"ClassificationList","value":""},{"name":"EnableGroupCreation","value":"true"}]}'
                    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -AsApp $true -Type POST -Body $CurrentState -ContentType 'application/json'
                    $CurrentState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'
                }
                ($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value = 'false'
                if ($DesiredGroupId) {
                    ($CurrentState.values | Where-Object { $_.name -eq 'GroupCreationAllowedGroupId' }).value = "$DesiredGroupId"
                }
                $body = "{values : $($CurrentState.values | ConvertTo-Json -Compress)}"
                $null = New-GraphPostRequest -tenantid $tenant -asApp $true -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -Type patch -Body $body -ContentType 'application/json'
                if ($DesiredGroupId) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled users from creating M365 Groups. Members of '$AllowedGroupName' remain allowed to create groups." -sev Info
                } else {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating M365 Groups.' -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating M365 Groups: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are disabled from creating M365 Groups.' -sev Info
        } elseif ($CreationDisabled -and -not $AllowedGroupCorrect) {
            Write-StandardsAlert -message "Users are disabled from creating M365 Groups, but the allowed group '$AllowedGroupName' is not configured as GroupCreationAllowedGroupId." -object ($CurrentState ?? @{CurrentState = $null }) -tenant $tenant -standardName 'DisableM365GroupUsers' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Users are disabled from creating M365 Groups, but the allowed group '$AllowedGroupName' is not configured." -sev Info
        } else {
            Write-StandardsAlert -message 'Users are not disabled from creating M365 Groups.' -object ($CurrentState ?? @{CurrentState = $null }) -tenant $tenant -standardName 'DisableM365GroupUsers' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from creating M365 Groups.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            M365GroupUserCreationDisabled = $CreationDisabled
        }
        $ExpectedValue = [PSCustomObject]@{
            M365GroupUserCreationDisabled = $true
        }
        # Only include the allowed-group comparison when a group is configured, so existing
        # deployments without one keep their original compare shape (backward compatible)
        if (-not [string]::IsNullOrWhiteSpace($AllowedGroupName)) {
            $CurrentValue | Add-Member -NotePropertyName AllowedCreationGroupCorrect -NotePropertyValue ([bool]$AllowedGroupCorrect)
            $ExpectedValue | Add-Member -NotePropertyName AllowedCreationGroupCorrect -NotePropertyValue $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableM365GroupUsers' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableM365GroupUsers' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
