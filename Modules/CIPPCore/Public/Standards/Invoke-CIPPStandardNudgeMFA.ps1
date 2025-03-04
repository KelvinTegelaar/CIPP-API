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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.NudgeMFA.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"number","name":"standards.NudgeMFA.snoozeDurationInDays","label":"Number of days to allow users to skip registering Authenticator (0-14, default is 1)","defaultValue":1}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-12-08
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

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
        $StateIsCorrect = ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq $state) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays -eq $Settings.snoozeDurationInDays) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.enforceRegistrationAfterAllowedSnoozes -eq $true)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to get Authenticator App Nudge state, check your permissions and try again' -sev Error -LogData (Get-CippException -Exception $_)
        Return
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'NudgeMFA: Invalid state parameter set' -sev Error
        Return
    }
    # Input validation
    if (([Int32]$Settings.snoozeDurationInDays -lt 0 -or [Int32]$Settings.snoozeDurationInDays -gt 15) -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'NudgeMFA: Invalid snoozeDurationInDays parameter set' -sev Error
        Return
    }

    if ($Settings.remediate -eq $true) {
        $StateName = $Settings.state.Substring(0, 1).ToUpper() + $Settings.state.Substring(1)
        if ($StateIsCorrect -eq $false) {
            try {
                $GraphRequest = @{
                    tenantid    = $Tenant
                    uri         = 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy'
                    AsApp       = $false
                    Type        = 'PATCH'
                    ContentType = 'application/json'
                    Body        = @{
                        registrationEnforcement = @{
                            authenticationMethodsRegistrationCampaign = @{
                                state                                  = $state
                                snoozeDurationInDays                   = $Settings.snoozeDurationInDays
                                enforceRegistrationAfterAllowedSnoozes = $true
                                includeTargets                         = $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.includeTargets
                                excludeTargets                         = $CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.excludeTargets
                            }
                        }
                    } | ConvertTo-Json -Depth 10 -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "$StateName Authenticator App Nudge with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Authenticator App Nudge to $state" -sev Error -LogData $_
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is already set to $state with a snooze duration of $($Settings.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Alert
        }
    }

}
