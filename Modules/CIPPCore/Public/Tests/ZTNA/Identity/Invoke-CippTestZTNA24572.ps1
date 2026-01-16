function Invoke-CippTestZTNA24572 {
    <#
    .SYNOPSIS
    Device enrollment notifications are enforced to ensure user awareness and secure onboarding
    #>
    param($Tenant)

    $TestId = 'ZTNA24572'
    #Tested
    try {
        $EnrollmentConfigs = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceEnrollmentConfigurations'

        if (-not $EnrollmentConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Device enrollment notifications are enforced to ensure user awareness and secure onboarding' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $EnrollmentNotifications = @($EnrollmentConfigs | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.windowsEnrollmentStatusScreenSettings' -or
                $_.'deviceEnrollmentConfigurationType' -eq 'EnrollmentNotificationsConfiguration'
            })

        $AssignedNotifications = @($EnrollmentNotifications | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedNotifications.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ At least one device enrollment notification is configured and assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No device enrollment notification is configured or assigned in Intune.`n`n"
        }

        if ($EnrollmentNotifications.Count -gt 0) {
            $ResultMarkdown += "## Device Enrollment Notifications`n`n"
            $ResultMarkdown += "| Policy Name | Assigned |`n"
            $ResultMarkdown += "| :---------- | :------- |`n"

            foreach ($policy in $EnrollmentNotifications) {
                $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $ResultMarkdown += "| $($policy.displayName) | $assigned |`n"
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Device enrollment notifications are enforced to ensure user awareness and secure onboarding' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Device enrollment notifications are enforced to ensure user awareness and secure onboarding' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
