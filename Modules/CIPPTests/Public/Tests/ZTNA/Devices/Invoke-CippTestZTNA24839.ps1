function Invoke-CippTestZTNA24839 {
    <#
    .SYNOPSIS
    Secure Wi-Fi profiles protect iOS devices from unauthorized network access
    #>
    param($Tenant)
    #Tested - Device

    $TestId = 'ZTNA24839'

    try {
        $DeviceConfigs = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        if (-not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Secure Wi-Fi profiles protect iOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data'
            return
        }

        $iOSWifiConfProfiles = @($DeviceConfigs | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.iosWiFiConfiguration' })
        $CompliantIosWifiConfProfiles = @($iOSWifiConfProfiles | Where-Object { $_.wiFiSecurityType -in @('wpa2Enterprise', 'wpaEnterprise') })
        $AssignedCompliantProfiles = @($CompliantIosWifiConfProfiles | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedCompliantProfiles.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ At least one Enterprise Wi-Fi profile for iOS exists and is assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No Enterprise Wi-Fi profile for iOS exists or none are assigned.`n`n"
        }

        if ($iOSWifiConfProfiles.Count -gt 0) {
            $ResultMarkdown += "## iOS WiFi Configuration Profiles`n`n"
            $ResultMarkdown += "| Policy Name | Wi-Fi Security Type | Assigned |`n"
            $ResultMarkdown += "| :---------- | :------------------ | :------- |`n"

            foreach ($policy in $iOSWifiConfProfiles) {
                $securityType = if ($policy.wiFiSecurityType) { $policy.wiFiSecurityType } else { 'Unknown' }
                $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $ResultMarkdown += "| $($policy.displayName) | $securityType | $assigned |`n"
            }
        } else {
            $ResultMarkdown += "No iOS WiFi configuration profiles found.`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Secure Wi-Fi profiles protect iOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Secure Wi-Fi profiles protect iOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data'
    }
}
