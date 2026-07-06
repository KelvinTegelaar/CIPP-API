function Invoke-CippTestE8_Admin_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML1) - Privileged accounts are blocked from authorising risky OAuth grants (ISM-1883)
    #>
    param($Tenant)

    $TestId = 'E8_Admin_04'
    $Name = 'User consent for risky OAuth applications is restricted (ISM-1883)'

    try {
        $AuthPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'
        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        $Cfg = $AuthPolicy | Select-Object -First 1
        $Permissions = $Cfg.defaultUserRolePermissions
        # The assigned consent policies live at the top level of the authorization policy, not under defaultUserRolePermissions.
        $UserConsent = $Cfg.permissionGrantPolicyIdsAssignedToDefaultUserRole

        $Issues = [System.Collections.Generic.List[string]]::new()
        if ($Permissions.allowedToCreateApps -eq $true) {
            $Issues.Add('defaultUserRolePermissions.allowedToCreateApps is true — non-admin users can register new applications.')
        }
        if ($Cfg.allowUserConsentForRiskyApps -eq $true) {
            $Issues.Add('allowUserConsentForRiskyApps is true — users can consent to applications Microsoft flags as risky.')
        }
        if ($UserConsent -contains 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy') {
            $Issues.Add('Legacy user consent policy in effect (`ManagePermissionGrantsForSelf.microsoft-user-default-legacy`). Switch to `microsoft-user-default-low` or admin-only.')
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'User consent for OAuth apps is restricted to low-impact (or admin-only).'
        } else {
            $Status = 'Failed'
            $Result = "Risky OAuth consent configuration:`n`n$(($Issues | ForEach-Object { "- $_" }) -join "`n")"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Restrict Admin Privileges'
    }
}
