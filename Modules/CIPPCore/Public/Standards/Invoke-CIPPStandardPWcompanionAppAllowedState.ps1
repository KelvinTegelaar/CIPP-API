function Invoke-CIPPStandardPWcompanionAppAllowedState {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $authenticatorFeaturesState = (New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type GET)
    $authstate = if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq 'enabled') { $true } else { $false }
    
    If ($Settings.remediate) {

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
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set companionAppAllowedState to $($Settings.state). Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($authstate) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'companionAppAllowedState' -FieldValue [bool]$authstate -StoreAs bool -Tenant $tenant
    }
}
