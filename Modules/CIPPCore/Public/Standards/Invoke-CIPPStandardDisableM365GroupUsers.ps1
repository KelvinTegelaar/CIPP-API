function Invoke-CIPPStandardDisableM365GroupUsers {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableM365GroupUsers
    .SYNOPSIS
        (Label) Disable M365 Group creation by users
    .DESCRIPTION
        (Helptext) Restricts M365 group creation to certain admin roles. This disables the ability to create Teams, SharePoint sites, Planner, etc
        (DocsDescription) Users by default are allowed to create M365 groups. This restricts M365 group creation to certain admin roles. This disables the ability to create Teams, SharePoint sites, Planner, etc
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CISA (MS.AAD.21.1v1)"
        EXECUTIVETEXT
            Restricts the creation of Microsoft 365 groups, Teams, and SharePoint sites to authorized administrators, preventing uncontrolled proliferation of collaboration spaces. This ensures proper governance, naming conventions, and resource management while maintaining oversight of all collaborative environments.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2022-07-17
        POWERSHELLEQUIVALENT
            Update-MgBetaDirectorySetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableM365GroupUsers' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
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

    if ($Settings.remediate -eq $true) {
        if (($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value -eq 'false') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already disabled from creating M365 Groups.' -sev Info
        } else {
            try {
                if (!$CurrentState) {
                    # If no current configuration is found, we set it to the default template supplied by MS.
                    $CurrentState = '{"id":"","displayName":"Group.Unified","templateId":"62375ab9-6b52-47ed-826b-58e47e0e304b","values":[{"name":"NewUnifiedGroupWritebackDefault","value":"true"},{"name":"EnableMIPLabels","value":"false"},{"name":"CustomBlockedWordsList","value":""},{"name":"EnableMSStandardBlockedWords","value":"false"},{"name":"ClassificationDescriptions","value":""},{"name":"DefaultClassification","value":""},{"name":"PrefixSuffixNamingRequirement","value":""},{"name":"AllowGuestsToBeGroupOwner","value":"false"},{"name":"AllowGuestsToAccessGroups","value":"true"},{"name":"GuestUsageGuidelinesUrl","value":""},{"name":"GroupCreationAllowedGroupId","value":""},{"name":"AllowToAddGuests","value":"true"},{"name":"UsageGuidelinesUrl","value":""},{"name":"ClassificationList","value":""},{"name":"EnableGroupCreation","value":"true"}]}'
                    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -AsApp $true -Type POST -Body $CurrentState -ContentType 'application/json'
                    $CurrentState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'
                }
                ($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value = 'false'
                $body = "{values : $($CurrentState.values | ConvertTo-Json -Compress)}"
                $null = New-GraphPostRequest -tenantid $tenant -asApp $true -Uri "https://graph.microsoft.com/beta/settings/$($CurrentState.id)" -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating M365 Groups.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating M365 Groups: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.alert -eq $true) {

        if ($CurrentState) {
            if (($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value -eq 'false') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are disabled from creating M365 Groups.' -sev Info
            } else {
                Write-StandardsAlert -message 'Users are not disabled from creating M365 Groups.' -object $CurrentState -tenant $tenant -standardName 'DisableM365GroupUsers' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from creating M365 Groups.' -sev Info
            }
        } else {
            Write-StandardsAlert -message 'Users are not disabled from creating M365 Groups.' -object @{CurrentState = $null } -tenant $tenant -standardName 'DisableM365GroupUsers' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from creating M365 Groups.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        if ($CurrentState) {
            if (($CurrentState.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value -eq 'false') {
                $CurrentState = $true
            } else {
                $CurrentState = $false
            }
        } else {
            $CurrentState = $false
        }

        $CurrentValue = [PSCustomObject]@{
            M365GroupUserCreationDisabled = $CurrentState
        }
        $ExpectedValue = [PSCustomObject]@{
            M365GroupUserCreationDisabled = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableM365GroupUsers' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableM365GroupUsers' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }

}
