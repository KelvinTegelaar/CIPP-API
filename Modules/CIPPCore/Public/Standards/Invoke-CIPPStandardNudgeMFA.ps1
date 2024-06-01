function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
    $State = if ($CurrentInfo.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq 'enabled') { $true } else { $false }

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

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}
