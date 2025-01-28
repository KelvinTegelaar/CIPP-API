function Invoke-CIPPStandardNudgeMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) NudgeMFA
    .SYNOPSIS
        (Label) Sets the state for the request to setup Authenticator
    .DESCRIPTION
        (Helptext) Sets the state of the registration campaign for the tenant
        (DocsDescription) Sets the state of the registration campaign for the tenant. If enabled nudges users to set up the Microsoft Authenticator during sign-in.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"label":"Select value","name":"standards.NudgeMFA.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"number","name":"standards.NudgeMFA.snoozeDurationInDays","label":"Number of days to allow users to skip registering Authenticator (0-14, default is 1)","default":1}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthenticationMethodPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'NudgeMFA'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
    $StateIsCorrect =   ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq $Settings.state) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays -eq $Settings.snoozeDurationInDays) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.enforceRegistrationAfterAllowedSnoozes -eq $true)

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }


    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'NudgeMFA: Invalid state parameter set' -sev Error
        Return
    }
    # Input validation
    if (([Int32]$Settings.snoozeDurationInDays -lt 0 -or [Int32]$Settings.snoozeDurationInDays -gt 15) -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'NudgeMFA: Invalid snoozeDurationInDays parameter set' -sev Error
        Return
    }


    If ($Settings.remediate -eq $true) {
        $StateName = $Settings.state.Substring(0, 1).ToUpper() + $Settings.state.Substring(1)
        if ($StatsIsCorrect -eq $false) {
            try {
                $GraphRequest = @{
                    tenantid = $tenant
                    uri = 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy'
                    AsApp = $false
                    Type = 'PATCH'
                    ContentType = 'application/json'
                    Body = @{
                        registrationEnforcement = @{
                            authenticationMethodsRegistrationCampaign = @{
                                state = $Settings.state
                                snoozeDurationInDays = $Settings.snoozeDurationInDays
                                enforceRegistrationAfterAllowedSnoozes = $true
                            }
                        }
                    } | ConvertTo-Json -Depth 10 -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -tenant $tenant -message "$StateName Authenticator App Nudge with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Authenticator App Nudge to $($Settings.state)" -sev Error -LogData $_
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is already set to $($Settings.state) with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Alert
        }
    }
}
