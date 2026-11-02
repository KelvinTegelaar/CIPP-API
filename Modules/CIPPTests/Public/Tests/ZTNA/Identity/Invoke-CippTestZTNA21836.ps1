function Invoke-CippTestZTNA21836 {
    <#
    .SYNOPSIS
    Workload Identities are not assigned privileged roles
    #>
    param($Tenant)
    #Untested
    $TestId = 'ZTNA21836'

    try {
        # Get privileged roles
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $PrivilegedRoles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Workload Identities are not assigned privileged roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        # Get workload identities (service principals) with privileged role assignments
        $WorkloadIdentitiesWithPrivilegedRoles = [System.Collections.Generic.List[object]]::new()

        foreach ($Role in $PrivilegedRoles) {
            # Must be the role's TEMPLATE id: PIM's roleDefinitionId carries template ids, so
            # passing $Role.id (the directoryRole instance id) matched nothing and this test found
            # no workload identities on any tenant.
            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.roleTemplateId

            foreach ($Member in $RoleMembers) {
                if ($Member.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                    # Get-CippDbRoleMembers returns id/displayName/appId — not principalId or
                    # principalDisplayName, which rendered blank here.
                    $WorkloadIdentitiesWithPrivilegedRoles.Add([PSCustomObject]@{
                            PrincipalId          = $Member.id
                            PrincipalDisplayName = $Member.displayName
                            AppId                = $Member.appId
                            RoleDisplayName      = $Role.displayName
                            RoleDefinitionId     = $Role.roleTemplateId
                            AssignmentType       = $Member.AssignmentType
                        })
                }
            }
        }

        $Passed = 'Passed'
        $ResultMarkdown = [System.Text.StringBuilder]::new()

        if ($WorkloadIdentitiesWithPrivilegedRoles.Count -gt 0) {
            $Passed = 'Failed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("**Found workload identities assigned to privileged roles.**`n")
            $null = $ResultMarkdown.Append("| Service Principal Name | Privileged Role | Assignment Type |`n")
            $null = $ResultMarkdown.Append("| :--- | :--- | :--- |`n")

            $SortedAssignments = $WorkloadIdentitiesWithPrivilegedRoles | Sort-Object -Property PrincipalDisplayName

            foreach ($Assignment in $SortedAssignments) {
                $SPLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($Assignment.PrincipalId)/appId/$($Assignment.AppId)"
                $null = $ResultMarkdown.Append("| [$($Assignment.PrincipalDisplayName)]($SPLink) | $($Assignment.RoleDisplayName) | $($Assignment.AssignmentType) |`n")
            }
            $null = $ResultMarkdown.Append("`n")
            $null = $ResultMarkdown.Append("`n**Recommendation:** Review and remove privileged role assignments from workload identities unless absolutely necessary. Use least-privilege principles and consider alternative approaches like managed identities with specific API permissions instead of directory roles.`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ **No workload identities found with privileged role assignments.**`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Workload Identities are not assigned privileged roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Workload Identities are not assigned privileged roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
