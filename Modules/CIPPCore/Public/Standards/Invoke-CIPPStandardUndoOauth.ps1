function Invoke-CIPPStandardUndoOauth {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        
        try {
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["ManagePermissionGrantsForSelf.microsoft-user-default-legacy"]}' -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode has been disabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Application Consent Mode to disabled Error: $($_.exception.message)" -sev Error
        }
    }

}
