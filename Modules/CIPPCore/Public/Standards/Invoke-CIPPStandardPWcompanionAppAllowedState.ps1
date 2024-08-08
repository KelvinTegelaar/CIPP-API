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
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Select value","name":"standards.PWcompanionAppAllowedState.state","values":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'PWcompanionAppAllowedState'

    $authenticatorFeaturesState = (New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type GET)
    $authstate = if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'companionAppAllowedState' -FieldValue $authstate -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'PWcompanionAppAllowedState: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {

        if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq $Settings.state) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "companionAppAllowedState is already set to the desired state of $($Settings.state)." -sev Info
        } else {
            try {
                # Remove number matching from featureSettings because this is now Microsoft enforced and shipping it returns an error
                $authenticatorFeaturesState.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
                # Define feature body
                $featureBody = @{
                    state         = $Settings.state
                    includeTarget = [PSCustomObject]@{
                        targetType = 'group'
                        id         = 'all_users'
                    }
                    excludeTarget = [PSCustomObject]@{
                        targetType = 'group'
                        id         = '00000000-0000-0000-0000-000000000000'
                    }
                }
                $authenticatorFeaturesState.featureSettings.companionAppAllowedState = $featureBody
                $body = ConvertTo-Json -Depth 3 -Compress -InputObject $authenticatorFeaturesState
                (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set companionAppAllowedState to $($Settings.state)." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set companionAppAllowedState to $($Settings.state). Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($authstate) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is not enabled.' -sev Alert
        }
    }
}
