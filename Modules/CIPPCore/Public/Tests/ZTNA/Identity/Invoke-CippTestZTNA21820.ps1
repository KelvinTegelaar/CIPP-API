function Invoke-CippTestZTNA21820 {
    <#
    .SYNOPSIS
    Activation alert for all privileged role assignments
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21820'

    try {
        # Get all privileged roles
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $PrivilegedRoles -or $PrivilegedRoles.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Activation alert for all privileged role assignments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
            return
        }

        # Get all role management policies
        $RoleManagementPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleManagementPolicies'

        # Build hashtable for quick policy lookup by role ID
        $PolicyByRoleId = @{}
        foreach ($Policy in $RoleManagementPolicies) {
            if ($Policy.scopeId -eq '/' -and $Policy.scopeType -eq 'DirectoryRole') {
                foreach ($RoleId in $Policy.effectiveRules.target.targetObjects.id) {
                    if ($RoleId) {
                        $PolicyByRoleId[$RoleId] = $Policy
                    }
                }
            }
        }

        $RolesWithIssues = [System.Collections.Generic.List[object]]::new()
        $Passed = 'Passed'

        foreach ($Role in $PrivilegedRoles) {
            $Policy = $PolicyByRoleId[$Role.id]

            if (-not $Policy) {
                $RolesWithIssues.Add(@{
                        Role                       = $Role
                        Issue                      = 'No PIM policy assignment found'
                        IsDefaultRecipientsEnabled = 'N/A'
                        NotificationRecipients     = 'N/A'
                    })
                continue
            }

            # Find notification rule for requestor end-user assignment
            $NotificationRule = $Policy.effectiveRules | Where-Object {
                $_.id -like '*Notification_Requestor_EndUser_Assignment*'
            }

            if ($NotificationRule) {
                $IsDefaultRecipientsEnabled = $NotificationRule.isDefaultRecipientsEnabled
                $NotificationRecipients = $NotificationRule.notificationRecipients

                # Check if alert is properly configured
                if ($IsDefaultRecipientsEnabled -eq $true -and ((-not $NotificationRecipients) -or $NotificationRecipients.Count -eq 0)) {
                    $Passed = 'Failed'
                    $RolesWithIssues.Add(@{
                            Role                       = $Role
                            IsDefaultRecipientsEnabled = $IsDefaultRecipientsEnabled
                            NotificationRecipients     = 'N/A'
                        })
                    # Exit early on first issue for performance
                    break
                }
            }
        }

        if ($RolesWithIssues.Count -eq 0) {
            $ResultMarkdown = 'Activation alerts are configured for privileged role assignments.'
        } else {
            $ResultMarkdown = 'Activation alerts are missing or improperly configured for privileged roles.'
        }

        if ($RolesWithIssues.Count -gt 0) {
            $ResultMarkdown += "`n`n## Roles with missing or misconfigured alerts`n`n"
            $ResultMarkdown += "| Role display name | Default recipients | Additional recipients |`n"
            $ResultMarkdown += "| :---------------- | :----------------- | :------------------- |`n"

            foreach ($RoleIssue in $RolesWithIssues) {
                $Role = $RoleIssue.Role
                $RoleLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles'
                $DisplayNameLink = "[$($Role.displayName)]($RoleLink)"

                $DefaultRecipientsStatus = if ($RoleIssue.IsDefaultRecipientsEnabled -eq $true) {
                    'Enabled'
                } else {
                    'Disabled'
                }
                $Recipients = $RoleIssue.NotificationRecipients

                $ResultMarkdown += "| $DisplayNameLink | $DefaultRecipientsStatus | $Recipients |`n"
            }
            $ResultMarkdown += "`n`n*Not all misconfigured roles may be listed. For performance reasons, this assessment stops at the first detected issue.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Low' -Name 'Activation alert for all privileged role assignments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Activation alert for all privileged role assignments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
    }
}
