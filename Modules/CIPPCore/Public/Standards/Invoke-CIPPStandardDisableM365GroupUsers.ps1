function Invoke-CIPPStandardDisableM365GroupUsers {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableM365GroupUsers
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Restricts M365 group creation to certain admin roles. This disables the ability to create Teams, Sharepoint sites, Planner, etc
    .DOCSDESCRIPTION
    Users by default are allowed to create M365 groups. This restricts M365 group creation to certain admin roles. This disables the ability to create Teams, SharePoint sites, Planner, etc
    .ADDEDCOMPONENT
    .LABEL
    Disable M365 Group creation by users
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaDirectorySetting
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Restricts M365 group creation to certain admin roles. This disables the ability to create Teams, Sharepoint sites, Planner, etc
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $tenant) | Where-Object -Property displayname -EQ 'Group.unified'

    If ($Settings.remediate -eq $true) {
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
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from creating M365 Groups.' -sev Alert
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not disabled from creating M365 Groups.' -sev Alert
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
        Add-CIPPBPAField -FieldName 'DisableM365GroupUsers' -FieldValue $CurrentState -StoreAs bool -Tenant $tenant
    }

}




