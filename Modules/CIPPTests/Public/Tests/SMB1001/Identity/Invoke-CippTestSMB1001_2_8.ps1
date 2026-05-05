function Invoke-CippTestSMB1001_2_8 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.8) - Management of remote access cloud credentials

    .DESCRIPTION
    Verifies the cloud IAM is configured with least privilege — regular users cannot create
    tenants, applications, or security groups, all of which are administrative actions that
    should be reserved for dedicated admin accounts. Implements the IAM scope of SMB1001 2.8.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_8'
    $Name = 'Cloud IAM is configured with least privilege'
    $Issues = [System.Collections.Generic.List[string]]::new()

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        if ($Cfg.defaultUserRolePermissions.allowedToCreateApps -ne $false) {
            $Issues.Add("Users can create app registrations (allowedToCreateApps: $($Cfg.defaultUserRolePermissions.allowedToCreateApps))")
        }
        if ($Cfg.defaultUserRolePermissions.allowedToCreateTenants -ne $false) {
            $Issues.Add("Users can create new M365 tenants (allowedToCreateTenants: $($Cfg.defaultUserRolePermissions.allowedToCreateTenants))")
        }
        if ($Cfg.defaultUserRolePermissions.allowedToCreateSecurityGroups -ne $false) {
            $Issues.Add("Users can create security groups (allowedToCreateSecurityGroups: $($Cfg.defaultUserRolePermissions.allowedToCreateSecurityGroups))")
        }
        if ($Cfg.allowedToSignUpEmailBasedSubscriptions -ne $false) {
            $Issues.Add("Users can sign up for self-service subscriptions (allowedToSignUpEmailBasedSubscriptions: $($Cfg.allowedToSignUpEmailBasedSubscriptions))")
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'Cloud IAM is configured with least privilege — users cannot create app registrations, tenants, security groups, or self-service subscriptions.'
        } else {
            $Status = 'Failed'
            $Result = "Cloud IAM grants users administrative-level capabilities that should be restricted to dedicated admin accounts:`n`n- $($Issues -join "`n- ")"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    }
}
