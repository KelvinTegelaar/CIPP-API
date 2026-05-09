function Invoke-CippTestCIS_5_2_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.1) - MFA SHALL be enabled for all users in administrative roles
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $CA -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ConditionalAccessPolicies or Roles) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'MFA is enabled for all users in administrative roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $PrivRoleIds = ($Roles | Where-Object { $_.isPrivileged -eq $true }).id

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.grantControls -and
            ($_.grantControls.builtInControls -contains 'mfa' -or $_.grantControls.authenticationStrength) -and
            $_.conditions.users.includeRoles -and
            (@($_.conditions.users.includeRoles) | Where-Object { $_ -in $PrivRoleIds }).Count -gt 0
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies enforce MFA on privileged roles:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets privileged roles with MFA. Create a policy with includeRoles = (privileged role IDs) and grant control = MFA.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'MFA is enabled for all users in administrative roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'MFA is enabled for all users in administrative roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
