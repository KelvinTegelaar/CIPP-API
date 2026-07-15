function Invoke-CippTestCIS_1_1_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (1.1.3) - Between two and four global admins SHALL be designated
    #>
    param($Tenant)

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if ($null -eq $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $GA = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1
        if (-not $GA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Global Administrator role not found in tenant role definitions.' -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $GAMembers = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($Member in @($GA.members)) {
            if ($Member.id) {
                [void]$GAMembers.Add([string]$Member.id)
            }
        }

        # roleDefinitionId carries the role's TEMPLATE id, not the directoryRole instance id, so
        # comparing it to $GA.id never matched and no PIM-assigned admin was ever counted here —
        # only the direct members above.
        foreach ($Assignment in @($RoleAssignmentScheduleInstances)) {
            if ($Assignment.roleDefinitionId -eq $GA.roleTemplateId -and $Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime -and $Assignment.principalId) {
                [void]$GAMembers.Add([string]$Assignment.principalId)
            }
        }

        $GACount = $GAMembers.Count

        if ($GACount -ge 2 -and $GACount -le 4) {
            $Status = 'Passed'
            $Result = "Tenant has $GACount Global Administrator(s) — within the recommended 2–4 range."
        } elseif ($GACount -lt 2) {
            $Status = 'Failed'
            $Result = "Tenant has only $GACount Global Administrator(s). At least 2 are required for redundancy."
        } else {
            $Status = 'Failed'
            $Result = "Tenant has $GACount Global Administrator(s). Maximum recommended is 4 — reduce role spread to lower the attack surface."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
    }
}
