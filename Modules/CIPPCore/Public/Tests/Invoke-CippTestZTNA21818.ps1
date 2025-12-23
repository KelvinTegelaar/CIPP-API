function Invoke-CippTestZTNA21818 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    $TestId = 'ZTNA21818'

    try {
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleManagementPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleManagementPolicies'

        $Notifications = @(
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as eligible to this role'
                NotificationType     = 'Role assignment alert'
                RuleId               = 'Notification_Admin_Admin_Eligibility'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as eligible to this role'
                NotificationType     = 'Notification to the assigned user (assignee)'
                RuleId               = 'Notification_Requestor_Admin_Eligibility'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as eligible to this role'
                NotificationType     = 'Request to approve a role assignment renewal/extension'
                RuleId               = 'Notification_Approver_Admin_Eligibility'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as active to this role'
                NotificationType     = 'Role assignment alert'
                RuleId               = 'Notification_Admin_Admin_Assignment'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as active to this role'
                NotificationType     = 'Notification to the assigned user (assignee)'
                RuleId               = 'Notification_Requestor_Admin_Assignment'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when members are assigned as active to this role'
                NotificationType     = 'Request to approve a role assignment renewal/extension'
                RuleId               = 'Notification_Approver_Admin_Assignment'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when eligible members activate this role'
                NotificationType     = 'Role activation alert'
                RuleId               = 'Notification_Admin_EndUser_Assignment'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when eligible members activate this role'
                NotificationType     = 'Notification to activated user (requestor)'
                RuleId               = 'Notification_Requestor_EndUser_Assignment'
            }
            [PSCustomObject]@{
                NotificationScenario = 'Send notifications when eligible members activate this role'
                NotificationType     = 'Request to approve an activation'
                RuleId               = 'Notification_Approver_EndUser_Assignment'
            }
        )

        $NotificationRules = [System.Collections.Generic.List[object]]::new()
        $Passed = $true
        $ExitLoop = $false

        foreach ($Role in $PrivilegedRoles) {
            $Policy = $RoleManagementPolicies | Where-Object {
                $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' -and $_.roleDefinitionId -eq $Role.id
            } | Select-Object -First 1

            if (-not $Policy) { continue }

            foreach ($NotificationRuleId in $Notifications.RuleId) {
                $Rule = $Policy.rules | Where-Object { $_.id -eq $NotificationRuleId } | Select-Object -First 1

                if ($Rule) {
                    $RuleWithRole = $Rule | Select-Object *, @{Name = 'RoleDisplayName'; Expression = { $Role.displayName } }
                    $NotificationRules.Add($RuleWithRole)

                    if ($Rule.isDefaultRecipientsEnabled -eq $true -and ($Rule.notificationRecipients.Count -eq 0 -or $null -eq $Rule.notificationRecipients)) {
                        $Passed = $false
                        $ExitLoop = $true
                        break
                    }
                }
            }

            if ($ExitLoop) { break }
        }

        if ($Passed) {
            $ResultMarkdown = "Role notifications are properly configured for privileged role.`n`n"
        } else {
            $ResultMarkdown = "Role notifications are not properly configured.`n`nNote: To save time, this check stops when it finds the first role that does not have notifications. After fixing this role and all other roles, we recommend running the check again to verify.`n`n"
        }

        $ResultMarkdown += "## Notifications for high privileged roles`n`n"
        $ResultMarkdown += "| Role Name | Notification Scenario | Notification Type | Default Recipients Enabled | Additional Recipients |`n"
        $ResultMarkdown += "| :-------- | :-------------------- | :---------------- | :------------------------- | :-------------------- |`n"

        foreach ($NotificationRule in $NotificationRules) {
            $MatchingNotification = $Notifications | Where-Object { $_.RuleId -eq $NotificationRule.id }
            $Recipients = if ($NotificationRule.notificationRecipients) { ($NotificationRule.notificationRecipients -join ', ') } else { '' }
            $ResultMarkdown += "| $($NotificationRule.roleDisplayName) | $($MatchingNotification.notificationScenario) | $($MatchingNotification.notificationType) | $($NotificationRule.isDefaultRecipientsEnabled) | $Recipients |`n"
        }

        return @{
            TestId         = $TestId
            Status         = if ($Passed) { 'Passed' } else { 'Failed' }
            ResultMarkdown = $ResultMarkdown
        }

    } catch {
        return @{
            TestId         = $TestId
            Status         = 'Failed'
            ResultMarkdown = "Error running test: $($_.Exception.Message)"
        }
    }
}
