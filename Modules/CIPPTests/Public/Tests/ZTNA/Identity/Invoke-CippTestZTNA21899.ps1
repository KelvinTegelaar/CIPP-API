function Invoke-CippTestZTNA21899 {
    <#
    .SYNOPSIS
    All privileged role assignments have a recipient that can receive notifications
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleManagementPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21899' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'All privileged role assignments have a recipient that can receive notifications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        # Policies expose a `rules` collection. Notification rules have @odata.type
        # '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule' and a
        # notificationRecipients collection. Empty notificationRecipients = nobody gets paged.
        $MissingRecipients = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $Rules = $Policy.rules
            if (-not $Rules) { continue }
            $NotifRules = $Rules.Where({ $_.'@odata.type' -eq '#microsoft.graph.unifiedRoleManagementPolicyNotificationRule' })
            foreach ($R in $NotifRules) {
                if (-not $R.notificationRecipients -or $R.notificationRecipients.Count -eq 0) {
                    $MissingRecipients.Add([PSCustomObject]@{
                            # 'policyId' — this type is sourced from roleManagementPolicyAssignments
                            # and carries the policy's id as policyId, not id.
                            PolicyId           = $Policy.policyId
                            ScopeId            = $Policy.scopeId
                            ScopeType          = $Policy.scopeType
                            RuleId             = $R.id
                            NotificationLevel  = $R.notificationLevel
                            NotificationType   = $R.notificationType
                            RecipientType      = $R.recipientType
                        })
                }
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($MissingRecipients.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $($Policies.Count) role management policy notification rule(s) have recipients configured.")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($MissingRecipients.Count) notification rule(s) across role management policies have no recipients configured.")
            $Lines.Add('')
            $Lines.Add('| Policy / Scope | Rule | Level | Type | Recipient Type |')
            $Lines.Add('| :------------- | :--- | :---- | :--- | :------------- |')
            foreach ($M in ($MissingRecipients | Select-Object -First 25)) {
                $Lines.Add("| $($M.ScopeType):$($M.ScopeId) | $($M.RuleId) | $($M.NotificationLevel) | $($M.NotificationType) | $($M.RecipientType) |")
            }
            if ($MissingRecipients.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($MissingRecipients.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Add at least one notification recipient (admin, requestor, or approver group) to each PIM notification rule so role activations and approvals raise alerts.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21899' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'Medium' -Name 'All privileged role assignments have a recipient that can receive notifications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21899' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'All privileged role assignments have a recipient that can receive notifications' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
