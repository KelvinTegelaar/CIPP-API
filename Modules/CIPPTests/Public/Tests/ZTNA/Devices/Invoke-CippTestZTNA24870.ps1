function Invoke-CippTestZTNA24870 {
    <#
    .SYNOPSIS
    Secure Wi-Fi profiles protect macOS devices from unauthorized network access
    #>
    param($Tenant)

    $TestId = 'ZTNA24870'
    #Tested - Device

    try {
        $DeviceConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        if (-not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Secure Wi-Fi profiles protect macOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data'
            return
        }

        $MacOSWifiConfProfiles = @($DeviceConfigs | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.macOSWiFiConfiguration' })
        $CompliantMacOSWifiConfProfiles = @($MacOSWifiConfProfiles | Where-Object { $_.wiFiSecurityType -eq 'wpaEnterprise' })
        $AssignedCompliantProfiles = @($CompliantMacOSWifiConfProfiles | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedCompliantProfiles.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ At least one Enterprise Wi-Fi profile for macOS exists and is assigned.`n`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("❌ No Enterprise Wi-Fi profile for macOS exists or none are assigned.`n`n")
        }

        if ($CompliantMacOSWifiConfProfiles.Count -gt 0) {
            $null = $ResultMarkdown.Append("## macOS WiFi Configuration Profiles`n`n")
            $null = $ResultMarkdown.Append("| Policy Name | Wi-Fi Security Type | Assigned |`n")
            $null = $ResultMarkdown.Append("| :---------- | :------------------ | :------- |`n")

            foreach ($policy in $CompliantMacOSWifiConfProfiles) {
                $securityType = if ($policy.wiFiSecurityType) { $policy.wiFiSecurityType } else { 'Unknown' }
                $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $null = $ResultMarkdown.Append("| $($policy.displayName) | $securityType | $assigned |`n")
            }
        } else {
            $null = $ResultMarkdown.Append("No compliant macOS Enterprise WiFi configuration profiles found.`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Secure Wi-Fi profiles protect macOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Secure Wi-Fi profiles protect macOS devices from unauthorized network access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data'
    }
}
