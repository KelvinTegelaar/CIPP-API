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
            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.id

            foreach ($Member in $RoleMembers) {
                if ($Member.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                    $WorkloadIdentitiesWithPrivilegedRoles.Add([PSCustomObject]@{
                            PrincipalId          = $Member.principalId
                            PrincipalDisplayName = $Member.principalDisplayName
                            AppId                = $Member.appId
                            RoleDisplayName      = $Role.displayName
                            RoleDefinitionId     = $Role.id
                            AssignmentType       = $Member.AssignmentType
                        })
                }
            }
        }

        $Passed = 'Passed'
        $ResultMarkdown = ''

        if ($WorkloadIdentitiesWithPrivilegedRoles.Count -gt 0) {
            $Passed = 'Failed'
            $ResultMarkdown = "**Found workload identities assigned to privileged roles.**`n"
            $ResultMarkdown += "| Service Principal Name | Privileged Role | Assignment Type |`n"
            $ResultMarkdown += "| :--- | :--- | :--- |`n"

            $SortedAssignments = $WorkloadIdentitiesWithPrivilegedRoles | Sort-Object -Property PrincipalDisplayName

            foreach ($Assignment in $SortedAssignments) {
                $SPLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($Assignment.PrincipalId)/appId/$($Assignment.AppId)/preferredSingleSignOnMode~/null/servicePrincipalType/Application/fromNav/"
                $ResultMarkdown += "| [$($Assignment.PrincipalDisplayName)]($SPLink) | $($Assignment.RoleDisplayName) | $($Assignment.AssignmentType) |`n"
            }
            $ResultMarkdown += "`n"
            $ResultMarkdown += "`n**Recommendation:** Review and remove privileged role assignments from workload identities unless absolutely necessary. Use least-privilege principles and consider alternative approaches like managed identities with specific API permissions instead of directory roles.`n"
        } else {
            $ResultMarkdown = "✅ **No workload identities found with privileged role assignments.**`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Workload Identities are not assigned privileged roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Workload Identities are not assigned privileged roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
