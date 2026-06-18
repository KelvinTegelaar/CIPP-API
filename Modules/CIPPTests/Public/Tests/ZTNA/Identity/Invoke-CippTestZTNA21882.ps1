function Invoke-CippTestZTNA21882 {
    <#
    .SYNOPSIS
    No nested groups in PIM for groups
    #>
    param($Tenant)

    try {
        $Groups = Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups'

        if (-not $Groups) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21882' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'No nested groups in PIM for groups' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        # Role-assignable groups are the ones eligible for PIM-for-Groups.
        # A nested group member is one without a userPrincipalName (the Groups cache only
        # selects id/displayName/userPrincipalName, so missing UPN strongly implies a group).
        $RoleAssignableGroups = $Groups.Where({ $_.isAssignableToRole -eq $true })

        if ($RoleAssignableGroups.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21882' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No role-assignable groups found in the tenant.' -Risk 'Medium' -Name 'No nested groups in PIM for groups' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $NestedGroups = [System.Collections.Generic.List[object]]::new()
        foreach ($G in $RoleAssignableGroups) {
            $Members = $G.members
            if (-not $Members) { continue }
            $GroupMembers = $Members.Where({ [string]::IsNullOrEmpty($_.userPrincipalName) })
            if ($GroupMembers.Count -gt 0) {
                $NestedGroups.Add([PSCustomObject]@{
                        Group        = $G
                        NestedCount  = $GroupMembers.Count
                        NestedSample = ($GroupMembers | Select-Object -First 3).displayName -join ', '
                    })
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($NestedGroups.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $($RoleAssignableGroups.Count) role-assignable group(s) contain only direct user members — no nested groups detected.")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($NestedGroups.Count) of $($RoleAssignableGroups.Count) role-assignable group(s) contain nested group members.")
            $Lines.Add('')
            $Lines.Add('| Group | Nested Members | Sample |')
            $Lines.Add('| :---- | :------------- | :----- |')
            foreach ($Entry in ($NestedGroups | Select-Object -First 25)) {
                $Lines.Add("| $($Entry.Group.displayName) | $($Entry.NestedCount) | $($Entry.NestedSample) |")
            }
            if ($NestedGroups.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($NestedGroups.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Replace nested-group memberships in role-assignable / PIM-managed groups with direct user assignments. Nesting bypasses the PIM activation flow for users in the nested group.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21882' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'Medium' -Name 'No nested groups in PIM for groups' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21882' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'No nested groups in PIM for groups' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    }
}
