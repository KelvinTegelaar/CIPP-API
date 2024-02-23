function Invoke-CIPPStandardDisableTenantCreation {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    $State = $CurrentInfo.defaultUserRolePermissions.allowedToCreateTenants

    If ($Settings.remediate) {

        if ($State) {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateTenants":false}}'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating tenants.' -sev Info
                $State = $false
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating tenants:  $($_.exception.message)" -sev 'Error'
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already disabled from creating tenants.' -sev Info
        }
    }
    if ($Settings.alert) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create tenants.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create tenants.' -sev Info
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableTenantCreation' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
