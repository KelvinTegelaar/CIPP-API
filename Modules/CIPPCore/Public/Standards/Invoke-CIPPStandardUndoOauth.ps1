function Invoke-CIPPStandardUndoOauth {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentState = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy?$select=permissionGrantPolicyIdsAssignedToDefaultUserRole' 
    $State = if ($CurrentState.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy') { $true } else { $false }
    $State

    If ($Settings.remediate) {
        
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is already disabled.' -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type PATCH -Body '{"permissionGrantPolicyIdsAssignedToDefaultUserRole":["ManagePermissionGrantsForSelf.microsoft-user-default-legacy"]}' -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Application Consent Mode has been disabled.' -sev Info
                $CurrentState.permissionGrantPolicyIdsAssignedToDefaultUserRole = 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Application Consent Mode to disabled. Error: $($_.exception.message)" -sev Error
            }
        }

    }

    if ($Settings.alert) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is disabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Application Consent Mode is not disabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'UndoOauth' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
