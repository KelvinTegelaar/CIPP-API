function Invoke-CIPPStandardDisableSecurityGroupUsers {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already not allowed to create Security Groups.' -sev Info
        } else {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateSecurityGroups":false}}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating Security Groups.' -sev Info
                $CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups = $false
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating Security Groups: $($_.exception.message)" -sev 'Error'
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create Security Groups.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create Security Groups.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableSecurityGroupUsers' -FieldValue $CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -StoreAs bool -Tenant $tenant
    }
}
