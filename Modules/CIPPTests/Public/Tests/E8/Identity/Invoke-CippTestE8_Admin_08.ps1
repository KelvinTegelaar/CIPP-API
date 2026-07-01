function Invoke-CippTestE8_Admin_08 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML3) - Just-in-Time / PIM is used for highly privileged roles (ISM-1508)
    #>
    param($Tenant)

    $TestId = 'E8_Admin_08'
    $Name = 'Just-in-Time activation (PIM eligibility) is used for highly privileged roles'

    $HighlyPriv = @('Global Administrator','Privileged Role Administrator','Privileged Authentication Administrator','Conditional Access Administrator','Intune Administrator','Security Administrator')

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if (-not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles) not found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Restrict Admin Privileges'
            return
        }

        # Without PIM active-assignment data we cannot distinguish permanent assignments from
        # PIM-eligible activation, so treating a missing cache as "compliant" would be a false pass.
        if (-not $RoleAssignmentScheduleInstances) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'RoleAssignmentScheduleInstances (PIM active assignments) cache not found — cannot verify whether highly-privileged roles use Just-in-Time activation.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Restrict Admin Privileges'
            return
        }

        $TargetRoles = $Roles | Where-Object { $_.displayName -in $HighlyPriv }
        if (-not $TargetRoles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No highly-privileged roles found in cache.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Restrict Admin Privileges'
            return
        }

        # RoleAssignmentScheduleInstances.roleDefinitionId is a role template ID, not a directory role instance ID.
        $TargetRoleTemplates = @{}
        foreach ($R in $TargetRoles) {
            $Tid = if ($R.roleTemplateId) { [string]$R.roleTemplateId } elseif ($R.RoletemplateId) { [string]$R.RoletemplateId } else { $null }
            if ($Tid) { $TargetRoleTemplates[$Tid] = $R.displayName }
        }
        $PermanentByRole = @{}
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $TargetRoleTemplates.ContainsKey([string]$A.roleDefinitionId)) {
                $key = [string]$A.roleDefinitionId
                if (-not $PermanentByRole.ContainsKey($key)) { $PermanentByRole[$key] = [System.Collections.Generic.HashSet[string]]::new() }
                [void]$PermanentByRole[$key].Add([string]$A.principalId)
            }
        }

        $RolesWithPermanent = foreach ($Tid in $TargetRoleTemplates.Keys) {
            $count = if ($PermanentByRole.ContainsKey($Tid)) { $PermanentByRole[$Tid].Count } else { 0 }
            if ($count -gt 0) { [pscustomobject]@{ Role = $TargetRoleTemplates[$Tid]; Permanent = $count } }
        }

        if (-not $RolesWithPermanent) {
            $Status = 'Passed'
            $Result = "No permanent role assignments found for highly-privileged roles ($($TargetRoles.displayName -join ', ')). All access appears to be PIM-eligible."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("Permanent (non-PIM) assignments to highly-privileged roles:`n`n| Role | Permanent assignees |`n| :--- | :-----------------: |`n")
            foreach ($R in $RolesWithPermanent) { $null = $Sb.Append("| $($R.Role) | $($R.Permanent) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML3 - Restrict Admin Privileges'
    }
}
