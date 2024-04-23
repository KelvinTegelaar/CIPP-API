function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
    $State = if ($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate) {

        if ($Settings.state -ne $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -or $Settings.snoozeDurationInDays -ne $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays) {
            try {
                $Body = $CurrentInfo
                $body.registrationEnforcement.authenticationMethodsRegistrationCampaign.state = $Settings.state
                $body.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays = $Settings.snoozeDurationInDays

                $body = ConvertTo-Json -Depth 10 -InputObject ($body | Select-Object registrationEnforcement)
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "$($Settings.state) Authenticator App Nudge with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
                $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state = $Settings.state
                $CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays = $Settings.snoozeDurationInDays
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to $($Settings.state) Authenticator App Nudge: $($_.exception.message)" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is already set to $($Settings.state) with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.alert) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Alert
        }
    }
    
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
