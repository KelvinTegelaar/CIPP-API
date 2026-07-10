function Invoke-CippTestE8_Admin_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML1) - Privileged accounts are dedicated cloud-only accounts (ISM-0445)
    #>
    param($Tenant)

    $TestId = 'E8_Admin_01'
    $Name = 'Privileged accounts are dedicated cloud-only accounts (ISM-0445)'

    try {
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Roles -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles or Users) not found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        $PrivRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        $PrivUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Role in @($Roles)) {
            $RoleTemplateId = if ($Role.roleTemplateId) { [string]$Role.roleTemplateId } elseif ($Role.RoletemplateId) { [string]$Role.RoletemplateId } else { $null }
            if ($RoleTemplateId) { [void]$PrivRoleIds.Add($RoleTemplateId) }
            foreach ($M in @($Role.members)) {
                if ($M.id) { [void]$PrivUserIds.Add([string]$M.id) }
            }
        }
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $PrivRoleIds.Contains([string]$A.roleDefinitionId)) {
                [void]$PrivUserIds.Add([string]$A.principalId)
            }
        }
        $PrivUsers = $Users | Where-Object { $PrivUserIds.Contains($_.id) }

        if (-not $PrivUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No privileged users found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Restrict Admin Privileges'
            return
        }

        $NonCompliant = $PrivUsers | Where-Object { $_.onPremisesSyncEnabled -eq $true }

        if (-not $NonCompliant) {
            $Status = 'Passed'
            $Result = "All $($PrivUsers.Count) privileged user(s) are cloud-only."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($NonCompliant.Count) of $($PrivUsers.Count) privileged user(s) are synced from on-premises Active Directory:`n`n| UPN |`n| :-- |`n")
            foreach ($U in ($NonCompliant | Select-Object -First 50)) { $null = $Sb.Append("| $($U.userPrincipalName) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Restrict Admin Privileges'
    }
}
