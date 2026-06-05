function Invoke-CippTestCIS_5_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.3.1) - Privileged role assignments SHALL be activated and not assigned
    #>
    param($Tenant)

    try {
        $Active = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $Active) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'RoleAssignmentScheduleInstances cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Privileged role assignments are activated and not assigned' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
            return
        }

        $GaTemplateId = '62e90394-69f5-4237-9190-012177145e10'

        # Map roleDefinitionId (equals roleTemplateId for built-in roles) to a display name.
        $RoleNames = @{}
        foreach ($r in $Roles) {
            if ($r.roleTemplateId) { $RoleNames[$r.roleTemplateId] = $r.displayName }
        }

        # Privileged roles whose active assignments must be JIT-activated rather than permanently assigned.
        $PrivilegedRoleNames = @(
            'Global Administrator', 'Privileged Role Administrator', 'Privileged Authentication Administrator',
            'Security Administrator', 'Exchange Administrator', 'SharePoint Administrator', 'User Administrator',
            'Conditional Access Administrator', 'Application Administrator', 'Cloud Application Administrator',
            'Hybrid Identity Administrator', 'Intune Administrator', 'Authentication Administrator',
            'Helpdesk Administrator', 'Password Administrator', 'Domain Name Administrator'
        )

        # Standing (permanent) active assignments = assignmentType 'Assigned' with no end date.
        $Permanent = @($Active | Where-Object { $_.assignmentType -eq 'Assigned' -and [string]::IsNullOrEmpty($_.endDateTime) })

        $GaPermanent = @($Permanent | Where-Object { $_.roleDefinitionId -eq $GaTemplateId })
        $OtherPrivPermanent = @($Permanent | Where-Object {
                $_.roleDefinitionId -ne $GaTemplateId -and $PrivilegedRoleNames -contains $RoleNames[$_.roleDefinitionId]
            })

        $Violations = @()
        if ($GaPermanent.Count -gt 2) {
            $Violations += "$($GaPermanent.Count) permanent Global Administrator assignments (only up to 2 break-glass accounts may be permanently assigned)."
        }
        if ($OtherPrivPermanent.Count -gt 0) {
            $Names = ($OtherPrivPermanent | ForEach-Object { $RoleNames[$_.roleDefinitionId] } | Sort-Object -Unique) -join ', '
            $Violations += "$($OtherPrivPermanent.Count) permanent assignment(s) in privileged roles that should use PIM activation: $Names."
        }

        if ($Violations.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No non-compliant standing privileged assignments found (Global Administrator permanent assignments: $($GaPermanent.Count)/2 break-glass). Confirm any remaining privileged roles use eligible (PIM) assignments."
        } else {
            $Status = 'Failed'
            $Result = "Standing privileged role assignments should be moved to PIM eligibility (activated, not permanently assigned):`n`n- " + ($Violations -join "`n- ")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Privileged role assignments are activated and not assigned' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged role assignments are activated and not assigned' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
    }
}
