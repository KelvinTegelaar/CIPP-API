function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    NudgeMFA
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Sets the state of the registration campaign for the tenant
    .DOCSDESCRIPTION
    Sets the state of the registration campaign for the tenant. If enabled nudges users to set up the Microsoft Authenticator during sign-in.
    .ADDEDCOMPONENT
    {"type":"Select","label":"Select value","name":"standards.NudgeMFA.state","values":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
    {"type":"number","name":"standards.NudgeMFA.snoozeDurationInDays","label":"Number of days to allow users to skip registering Authenticator (0-14, default is 1)","default":1}
    .LABEL
    Sets the state for the request to setup Authenticator
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgPolicyAuthenticationMethodPolicy
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the state of the registration campaign for the tenant
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
    $State = if ($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $State -StoreAs bool -Tenant $tenant
    }


    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'NudgeMFA: Invalid state parameter set' -sev Error
        Return
    }
    # Input validation
    if (($Settings.snoozeDurationInDays -lt 0 -or $Settings.snoozeDurationInDays -gt 15) -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'NudgeMFA: Invalid snoozeDurationInDays parameter set' -sev Error
        Return
    }


    If ($Settings.remediate -eq $true) {

        $StateName = $Settings.state.Substring(0, 1).ToUpper() + $Settings.state.Substring(1)
        if ($Settings.state -ne $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -or $Settings.snoozeDurationInDays -ne $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays) {
            try {
                $Body = $CurrentInfo
                $body.registrationEnforcement.authenticationMethodsRegistrationCampaign.state = $Settings.state
                $body.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays = $Settings.snoozeDurationInDays

                $body = ConvertTo-Json -Depth 10 -InputObject ($body | Select-Object registrationEnforcement)
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "$StateName Authenticator App Nudge with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
                $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state = $Settings.state
                $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays = $Settings.snoozeDurationInDays
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Authenticator App Nudge to $($Settings.state): $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is already set to $($Settings.state) with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Alert
        }
    }
}




