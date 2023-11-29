param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.PWcompanionAppAllowedState
if (!$Setting) {
    $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.PWcompanionAppAllowedState
}

try {

    # Get current state of microsoftAuthenticator policy
    $authenticatorFeaturesState = (New-GraphGetRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type GET)

    # Remove number matching from featureSettings because this is now Microsoft enforced and shipping it returns an error
    $authenticatorFeaturesState.featureSettings.PSObject.Properties.Remove('numberMatchingRequiredState')

    # Define feature body
    $featureBody = @{
        state = $Setting.state
        includeTarget = [PSCustomObject]@{
            targetType = 'group'
            id = 'all_users'
        }
        excludeTarget = [PSCustomObject]@{
            targetType = 'group'
            id = '00000000-0000-0000-0000-000000000000'
        }
    }

    # Set body for companionAppAllowedState
    $authenticatorFeaturesState.featureSettings.companionAppAllowedState = $featureBody

    $body = $authenticatorFeaturesState | ConvertTo-Json -Depth 3

    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage  -API "Standards" -tenant $tenant -message "Enabled companionAppAllowedState." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable companionAppAllowedState. Error: $($_.exception.message)" -sev Error
}