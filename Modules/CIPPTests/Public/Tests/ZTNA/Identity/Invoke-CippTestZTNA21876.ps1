function Invoke-CippTestZTNA21876 {
    <#
    .SYNOPSIS
    Use PIM for Microsoft Entra privileged roles
    #>
    param($Tenant)

    try {
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'

        if (-not $RoleAssignments) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21876' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Use PIM for Microsoft Entra privileged roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        # Well-known privileged role template IDs.
        $PrivilegedRoleTemplateIds = @(
            '62e90394-69f5-4237-9190-012177145e10' # Global Administrator
            'e8611ab8-c189-46e8-94e1-60213ab1f814' # Privileged Role Administrator
            '194ae4cb-b126-40b2-bd5b-6091b380977d' # Security Administrator
            'fe930be7-5e62-47db-91af-98c3a49a38b1' # User Administrator
            '729827e3-9c14-49f7-bb1b-9608f156bbb8' # Helpdesk Administrator
            'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' # SharePoint Administrator
            '29232cdf-9323-42fd-ade2-1d097af3e4de' # Exchange Administrator
            '69091246-20e8-4a56-aa4d-066075b2a7a8' # Teams Administrator
            '158c047a-c907-4556-b7ef-446551a6b5f7' # Cloud Application Administrator
            '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' # Application Administrator
            'b0f54661-2d74-4c50-afa3-1ec803f12efe' # Billing Administrator
            'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9' # Conditional Access Administrator
            '966707d0-3269-4727-9be2-8c3a10f19b9d' # Password Administrator
            'e3973bdf-4987-49ae-837a-ba8e231c7286' # Azure DevOps Administrator
            '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' # Privileged Authentication Administrator
        )

        $PermanentToPrivileged = [System.Collections.Generic.List[object]]::new()
        foreach ($A in $RoleAssignments) {
            if ($A.roleDefinitionId -notin $PrivilegedRoleTemplateIds) { continue }
            if ($A.assignmentType -eq 'Assigned' -and $A.memberType -in 'Direct', 'Group') {
                $PermanentToPrivileged.Add($A)
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($PermanentToPrivileged.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add('No permanent (non-PIM) assignments found for privileged Microsoft Entra roles.')
        } else {
            $Status = 'Failed'
            $Lines.Add("$($PermanentToPrivileged.Count) permanent assignment(s) found for privileged Microsoft Entra roles. These should be managed via PIM eligibility instead.")
            $Lines.Add('')
            $Lines.Add('| Principal | Role Definition ID | Assignment Type | Member Type |')
            $Lines.Add('| :-------- | :----------------- | :-------------- | :---------- |')
            foreach ($A in ($PermanentToPrivileged | Select-Object -First 25)) {
                $Lines.Add("| $($A.principalId) | $($A.roleDefinitionId) | $($A.assignmentType) | $($A.memberType) |")
            }
            if ($PermanentToPrivileged.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($PermanentToPrivileged.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Move standing privileged role assignments into PIM as eligible assignments so users must activate the role just-in-time with MFA and approval.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21876' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'Medium' -Name 'Use PIM for Microsoft Entra privileged roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21876' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Use PIM for Microsoft Entra privileged roles' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
