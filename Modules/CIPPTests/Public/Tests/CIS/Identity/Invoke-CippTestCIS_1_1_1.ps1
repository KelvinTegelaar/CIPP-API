function Invoke-CippTestCIS_1_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.1.1) - Administrative accounts SHALL be cloud-only

    .DESCRIPTION
    Privileged role holders should be cloud-only accounts (no onPremisesSyncEnabled),
    use a *.onmicrosoft.com UPN, and have no licenses assigned that grant access to user
    productivity applications.
    #>
    param($Tenant)

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Roles -or -not $RoleAssignments -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles, RoleAssignments, or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $PrivilegedRoleIds = ($Roles | Where-Object { $_.isPrivileged -eq $true }).id
        $PrivilegedAssignments = $RoleAssignments | Where-Object { $_.roleDefinitionId -in $PrivilegedRoleIds }
        $PrivilegedUserIds = $PrivilegedAssignments.principalId | Select-Object -Unique
        $PrivilegedUsers = $Users | Where-Object { $_.id -in $PrivilegedUserIds }

        if (-not $PrivilegedUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No privileged users found.' -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $NonCompliant = $PrivilegedUsers | Where-Object {
            $_.onPremisesSyncEnabled -eq $true -or
            $_.userPrincipalName -notlike '*onmicrosoft.com' -or
            ($_.assignedLicenses -and $_.assignedLicenses.Count -gt 0)
        }

        if ($NonCompliant.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($PrivilegedUsers.Count) privileged users are cloud-only and unlicensed."
        } else {
            $Status = 'Failed'
            $Result = "$($NonCompliant.Count) of $($PrivilegedUsers.Count) privileged user(s) are not cloud-only or are licensed:`n`n"
            $Result += "| UPN | Synced | Licensed |`n| :-- | :----- | :------- |`n"
            foreach ($U in ($NonCompliant | Select-Object -First 25)) {
                $Result += "| $($U.userPrincipalName) | $([bool]$U.onPremisesSyncEnabled) | $([bool]($U.assignedLicenses.Count -gt 0)) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
