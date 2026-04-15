function Invoke-CippTestZTNA21819 {
    <#
    .SYNOPSIS
    Activation alert for Global Administrator role assignment
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21819'

    try {
        # Get Global Administrator role (template ID: 62e90394-69f5-4237-9190-012177145e10)
        $Roles = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Roles'
        $GlobalAdminRole = $Roles | Where-Object { $_.roleTemplateId -eq '62e90394-69f5-4237-9190-012177145e10' }

        if (-not $GlobalAdminRole) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Activation alert for Global Administrator role assignment' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
            return
        }

        # Get role management policy for Global Admin
        $RoleManagementPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleManagementPolicies'
        $GlobalAdminPolicy = $RoleManagementPolicies | Where-Object {
            $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' -and $_.effectiveRules.target.targetObjects.id -contains $GlobalAdminRole.id
        }

        $Passed = 'Failed'
        $IsDefaultRecipientsEnabled = 'N/A'
        $Recipients = 'N/A'

        if ($GlobalAdminPolicy) {
            # Find the notification rule for requestor end-user assignment
            $NotificationRule = $GlobalAdminPolicy.effectiveRules | Where-Object {
                $_.id -like '*Notification_Requestor_EndUser_Assignment*'
            }

            if ($NotificationRule) {
                $IsDefaultRecipientsEnabled = $NotificationRule.isDefaultRecipientsEnabled
                $NotificationRecipients = $NotificationRule.notificationRecipients

                if ($NotificationRecipients) {
                    $Recipients = ($NotificationRecipients -join ', ')
                }

                if ($NotificationRecipients -or $IsDefaultRecipientsEnabled) {
                    $Passed = 'Passed'
                }
            }
        }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "Activation alerts are configured for Global Administrator role.`n`n"
        } else {
            $ResultMarkdown = "Activation alerts are missing or improperly configured for Global Administrator role.`n`n"
        }

        $ResultMarkdown += "| Role display name | Default recipients | Additional recipients |`n"
        $ResultMarkdown += "| :---------------- | :----------------- | :------------------- |`n"

        $RoleLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles'
        $DisplayNameLink = "[$($GlobalAdminRole.displayName)]($RoleLink)"

        $DefaultRecipientsStatus = if ($IsDefaultRecipientsEnabled -eq $true) {
            '✅ Enabled'
        } elseif ($IsDefaultRecipientsEnabled -eq $false) {
            '❌ Disabled'
        } else {
            'N/A'
        }

        $RecipientsDisplay = if ([string]::IsNullOrEmpty($Recipients) -or $Recipients -eq 'N/A') {
            '-'
        } else {
            $Recipients
        }

        $ResultMarkdown += "| $DisplayNameLink | $DefaultRecipientsStatus | $RecipientsDisplay |`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Low' -Name 'Activation alert for Global Administrator role assignment' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Activation alert for Global Administrator role assignment' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
    }
}
