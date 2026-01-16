function Invoke-CippTestZTNA24576 {
    <#
    .SYNOPSIS
    Endpoint Analytics is enabled to help identify risks on Windows devices
    #>
    param($Tenant)

    $TestId = 'ZTNA24576'
    #Tested - Device

    try {
        $DeviceConfigs = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        if (-not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Endpoint Analytics is enabled to help identify risks on Windows devices' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $WindowsHealthMonitoringPolicies = @($DeviceConfigs | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.windowsHealthMonitoringConfiguration'
            })

        $AssignedPolicies = @($WindowsHealthMonitoringPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ An Endpoint analytics policy is created and assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ Endpoint analytics policy is not created or not assigned.`n`n"
        }

        if ($WindowsHealthMonitoringPolicies.Count -gt 0) {
            $ResultMarkdown += "## Endpoint Analytics Policies`n`n"
            $ResultMarkdown += "| Policy Name | Assigned |`n"
            $ResultMarkdown += "| :---------- | :------- |`n"

            foreach ($policy in $WindowsHealthMonitoringPolicies) {
                $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $ResultMarkdown += "| $($policy.displayName) | $assigned |`n"
            }
        } else {
            $ResultMarkdown += "No Endpoint Analytics policies found in this tenant.`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'Low' -Name 'Endpoint Analytics is enabled to help identify risks on Windows devices' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Endpoint Analytics is enabled to help identify risks on Windows devices' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
