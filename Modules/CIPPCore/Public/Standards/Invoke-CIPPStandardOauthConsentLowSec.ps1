function Invoke-CIPPStandardOauthConsentLowSec {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $State = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $tenant)
    If ($Settings.remediate -eq $true) {
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
    if ($Settings.alert -eq $true) {

        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is not enabled.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode(microsoft-user-default-low) is enabled.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        if ($State.permissionGrantPolicyIdsAssignedToDefaultUserRole -notin @('managePermissionGrantsForSelf.microsoft-user-default-low')) {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $false
        } else {
            $State.permissionGrantPolicyIdsAssignedToDefaultUserRole = $true
        }
        Add-CIPPBPAField -FieldName 'OauthConsentLowSec' -FieldValue $State.permissionGrantPolicyIdsAssignedToDefaultUserRole -StoreAs bool -Tenant $tenant
    }
}
