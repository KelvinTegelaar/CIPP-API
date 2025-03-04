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
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.PWcompanionAppAllowedState.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'PWcompanionAppAllowedState'

    $authenticatorFeaturesState = (New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type GET)
    $authState = if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'companionAppAllowedState' -FieldValue $authState -StoreAs bool -Tenant $Tenant
    }

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PWcompanionAppAllowedState: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {

        if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq $state) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "companionAppAllowedState is already set to the desired state of $state." -sev Info
        } else {
            try {
                # Remove number matching from featureSettings because this is now Microsoft enforced and shipping it returns an error
                $authenticatorFeaturesState.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
                # Define feature body
                $featureBody = @{
                    state         = $state
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
                $null = (New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set companionAppAllowedState to $state." -sev Info
            } catch {
                $ErrorMessage = Get-CippExceptionMessage -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set companionAppAllowedState to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($authState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'companionAppAllowedState is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'companionAppAllowedState is not enabled.' -sev Alert
        }
    }
}
