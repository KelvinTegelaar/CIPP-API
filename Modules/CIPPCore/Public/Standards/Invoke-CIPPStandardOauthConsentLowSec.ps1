function Invoke-OauthConsentLowSec {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $State = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant)
    If ($Settings.Remediate) {
        try {
            if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
                Write-Host 'Going to set'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["managePermissionGrantsForSelf.microsoft-user-default-low"]}' -ContentType 'application/json'
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) has been enabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Application Consent Mode (microsoft-user-default-low) Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.Alert) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is not enabled.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is enabled.' -sev Info
        }
    }
}
