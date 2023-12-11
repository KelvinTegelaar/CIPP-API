function Invoke-CIPPStandardDisableTenantCreation {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        try {
            $body = '{"defaultUserRolePermissions":{"allowedToCreateTenants":false}}'
    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json')
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standards API: Disabled users from creating tenants.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating tenants:  $($_.exception.message)" -sev 'Error'
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateTenants -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create tenants.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create tenants.' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableTenantCreation' -FieldValue [bool]$CurrentInfo.defaultUserRolePermissions.allowedToCreateTenants -StoreAs bool -Tenant $tenant
    }
}
