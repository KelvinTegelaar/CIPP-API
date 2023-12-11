function Invoke-CIPPStandardPWcompanionAppAllowedState {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $authenticatorFeaturesState = (New-GraphGetRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type GET)
    If ($Settings.remediate) {
        $Setting = $Settings
        try {
            # Get current state of microsoftAuthenticator policy
            # Remove number matching from featureSettings because this is now Microsoft enforced and shipping it returns an error
            $authenticatorFeaturesState.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')
            # Define feature body
            $featureBody = @{
                state         = $Setting.state
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
            $body = $authenticatorFeaturesState | ConvertTo-Json -Depth 3
            (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -Type patch -Body $body -ContentType 'application/json')
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled companionAppAllowedState.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable companionAppAllowedState. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq 'enabled') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'companionAppAllowedState is not enabled.' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($authenticatorFeaturesState.featureSettings.companionAppAllowedState.state -eq 'enabled') { $authstate = $true } else { $authstate = $false }
        Add-CIPPBPAField -FieldName 'companionAppAllowedState' -FieldValue [bool]$authstate -StoreAs bool -Tenant $tenant
    }
}
