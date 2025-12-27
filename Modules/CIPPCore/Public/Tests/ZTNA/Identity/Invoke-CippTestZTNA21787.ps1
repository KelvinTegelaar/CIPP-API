function Invoke-CippTestZTNA21787 {
    param($Tenant)
    #tested
    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21787' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authorization policy not found in database' -Risk 'High' -Name 'Permissions to create new tenants are limited to the Tenant Creator role' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $CanCreateTenants = $AuthPolicy.defaultUserRolePermissions.allowedToCreateTenants

        if ($CanCreateTenants -eq $false) {
            $Status = 'Passed'
            $Result = 'Non-privileged users are restricted from creating tenants'
        } else {
            $Status = 'Failed'
            $Result = 'Non-privileged users are allowed to create tenants'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21787' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Permissions to create new tenants are limited to the Tenant Creator role' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21787' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Permissions to create new tenants are limited to the Tenant Creator role' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
