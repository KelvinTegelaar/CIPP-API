function Invoke-CIPPStandardPWcompanionAppAllowedState {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PWcompanionAppAllowedState
    .SYNOPSIS
        (Label) Set Authenticator Lite state
    .DESCRIPTION
        (Helptext) Sets the state of Authenticator Lite, Authenticator lite is a companion app for passwordless authentication.
        (DocsDescription) Sets the Authenticator Lite state to enabled. This allows users to use the Authenticator Lite built into the Outlook app instead of the full Authenticator app.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.PWcompanionAppAllowedState.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"},{"label":"Microsoft managed","value":"default"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-05-18
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $AuthenticatorFeaturesState = (New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator')

    # Get state value using null-coalescing operator
    $CurrentState = $AuthenticatorFeaturesState.featureSettings.companionAppAllowedState.state
    $WantedState = $Settings.state.value ? $Settings.state.value : $settings.state
    $AuthStateCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($WantedState) -or $WantedState -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PWcompanionAppAllowedState: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {
        Write-Host "Remediating PWcompanionAppAllowedState for tenant $Tenant to $WantedState"

        if ($AuthStateCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "companionAppAllowedState is already set to the desired state of $WantedState." -sev Info
        } else {
            try {
                # Remove number matching from featureSettings because this is now Microsoft enforced and shipping it returns an error
                $AuthenticatorFeaturesState.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
                # Define feature body
                $featureBody = @{
                    state         = $WantedState
                    includeTarget = [PSCustomObject]@{
                        targetType = 'group'
                        id         = 'all_users'
                    }
                    excludeTarget = [PSCustomObject]@{
                        targetType = 'group'
                        id         = '00000000-0000-0000-0000-000000000000'
                    }
                }
                $AuthenticatorFeaturesState.featureSettings.companionAppAllowedState = $featureBody
                $body = ConvertTo-Json -Depth 3 -Compress -InputObject $AuthenticatorFeaturesState
                $null = (New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set companionAppAllowedState to $WantedState." -sev Info
            } catch {
                $ErrorMessage = Get-CippExceptionMessage -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set companionAppAllowedState to $WantedState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($AuthStateCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "companionAppAllowedState is set to $WantedState." -sev Info
        } else {
            Write-StandardsAlert -message "companionAppAllowedState is not set to $WantedState. Current state is $CurrentState." -object $AuthenticatorFeaturesState -tenant $Tenant -standardName 'PWcompanionAppAllowedState' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "companionAppAllowedState is not set to $WantedState. Current state is $CurrentState." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'companionAppAllowedState' -FieldValue $AuthStateCorrect -StoreAs bool -Tenant $Tenant
        if ($AuthStateCorrect -eq $true) {
            $FieldValue = $true
        } else {
            $FieldValue = $AuthenticatorFeaturesState.featureSettings.companionAppAllowedState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PWcompanionAppAllowedState' -FieldValue $FieldValue -Tenant $Tenant
    }
}
