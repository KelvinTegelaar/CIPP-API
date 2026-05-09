function Invoke-CippTestSMB1001_1_4 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.4) - Automatically install tested software updates and patches

    .DESCRIPTION
    Verifies that a Windows Update for Business configuration profile is deployed via Intune
    and assigned. The Intune update profile is stored in IntuneDeviceConfigurations under the
    '@odata.type' value '#microsoft.graph.windowsUpdateForBusinessConfiguration'.
    #>
    param($Tenant)

    $TestId = 'SMB1001_1_4'
    $Name = 'Software updates are installed automatically'

    try {
        $DeviceConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        if (-not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'IntuneDeviceConfigurations cache not found. This may be due to missing Intune licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $UpdatePolicies = @($DeviceConfigs | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' })

        if ($UpdatePolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows Update for Business configuration profiles found in Intune.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $Assigned = @($UpdatePolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })

        if ($Assigned.Count -gt 0) {
            $Status = 'Passed'
            $TableRows = foreach ($P in $UpdatePolicies) {
                $A = if ($P.assignments -and $P.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                "| $($P.displayName) | $A |"
            }
            $Result = (@(
                    "$($Assigned.Count) of $($UpdatePolicies.Count) Windows Update for Business profile(s) are assigned."
                    ''
                    '| Profile Name | Assigned |'
                    '| :----------- | :------- |'
                ) + $TableRows) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "Windows Update for Business profiles exist but none are assigned. Found $($UpdatePolicies.Count) unassigned profile(s)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
