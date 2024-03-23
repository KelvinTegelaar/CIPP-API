function Invoke-CIPPStandardDisableAppCreation {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy?$select=defaultUserRolePermissions' -tenantid $Tenant
    
    If ($Settings.remediate) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateApps -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already not allowed to create App registrations.' -sev Info
        } else {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateApps":false}}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'    
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating App registrations.' -sev Info
                $CurrentInfo.defaultUserRolePermissions.allowedToCreateApps = $false
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating App registrations: $($_.exception.message)" -sev Error
            }
        }
    }
        
    if ($Settings.alert) {

        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateApps -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create App registrations.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create App registrations.' -sev Alert
        }
    }

    if ($Settings.report) {
        $State = -not $CurrentInfo.defaultUserRolePermissions.allowedToCreateApps
        Add-CIPPBPAField -FieldName 'UserAppCreationDisabled' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
