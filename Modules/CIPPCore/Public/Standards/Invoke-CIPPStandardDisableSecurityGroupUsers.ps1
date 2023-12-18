function Invoke-CIPPStandardDisableSecurityGroupUsers {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        

        try {
            $body = '{"defaultUserRolePermissions":{"allowedToCreateSecurityGroups":false}}'
    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json')

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standards API: Disabled users from creating Security Groups.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating Security Groups: $($_.exception.message)" -sev 'Error'
        }
    }
        
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create Security Groups.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create Security Groups.' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableSecurityGroupUsers' -FieldValue [bool]$CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -StoreAs bool -Tenant $tenant
    }
}
