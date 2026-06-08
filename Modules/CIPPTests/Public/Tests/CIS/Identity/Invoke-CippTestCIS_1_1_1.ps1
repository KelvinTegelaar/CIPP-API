function Invoke-CippTestCIS_1_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (1.1.1) - Administrative accounts SHALL be cloud-only

    .DESCRIPTION
    Privileged role holders should be cloud-only accounts (no onPremisesSyncEnabled),
    use a *.onmicrosoft.com UPN, and have no licenses assigned that grant access to user
    productivity applications.
    #>
    param($Tenant)

    try {
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if ($null -eq $Roles -or $null -eq $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $PrivilegedRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        $PrivilegedUserIds = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($Role in @($Roles)) {
            $RoleTemplateId = if ($Role.roleTemplateId) { [string]$Role.roleTemplateId } elseif ($Role.RoletemplateId) { [string]$Role.RoletemplateId } else { $null }
            if ($RoleTemplateId) {
                [void]$PrivilegedRoleIds.Add($RoleTemplateId)
            }

            foreach ($Member in @($Role.members)) {
                if ($Member.id) {
                    [void]$PrivilegedUserIds.Add([string]$Member.id)
                }
            }
        }

        foreach ($Assignment in @($RoleAssignmentScheduleInstances)) {
            if ($Assignment.roleDefinitionId -and $Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime -and $PrivilegedRoleIds.Contains([string]$Assignment.roleDefinitionId) -and $Assignment.principalId) {
                [void]$PrivilegedUserIds.Add([string]$Assignment.principalId)
            }
        }

        $PrivilegedUsers = $Users.Where({ $PrivilegedUserIds.Contains($_.id) })

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
            $Result = [System.Text.StringBuilder]::new("All $($PrivilegedUsers.Count) privileged users are cloud-only and unlicensed.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($NonCompliant.Count) of $($PrivilegedUsers.Count) privileged user(s) are not cloud-only or are licensed:`n`n")
            $null = $Result.Append("| UPN | Synced | Licensed |`n| :-- | :----- | :------- |`n")
            foreach ($U in ($NonCompliant | Select-Object -First 25)) {
                $null = $Result.Append("| $($U.userPrincipalName) | $([bool]$U.onPremisesSyncEnabled) | $([bool]($U.assignedLicenses.Count -gt 0)) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Administrative accounts are cloud-only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
