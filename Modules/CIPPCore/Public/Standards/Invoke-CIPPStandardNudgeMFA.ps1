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
    Write-Host "NudgeMFA: $($Settings | ConvertTo-Json -Compress)"
    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
        $StateIsCorrect = ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.state -eq $state) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays -eq $Settings.snoozeDurationInDays) -and
                        ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.enforceRegistrationAfterAllowedSnoozes -eq $true)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to get Authenticator App Nudge state, check your permissions and try again' -sev Error -LogData (Get-CippException -Exception $_)
        exit 0
    }

    if ($Settings.remediate -eq $true) {
        $StateName = $Settings.state ? 'Enabled' : 'Disabled'
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
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Authenticator App Nudge to $state. Error: $($_.Exception.message)" -sev Error -LogData $_
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        } else {
            Write-StandardsAlert -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -object ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign | Select-Object snoozeDurationInDays, state) -tenant $Tenant -standardName 'NudgeMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Authenticator App Nudge is not enabled with a snooze duration of $($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign.snoozeDurationInDays)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ? $true : ($CurrentState.registrationEnforcement.authenticationMethodsRegistrationCampaign | Select-Object snoozeDurationInDays, state)
        Set-CIPPStandardsCompareField -FieldName 'standards.NudgeMFA' -FieldValue $state -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'NudgeMFA' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
