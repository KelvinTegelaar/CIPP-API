function Invoke-CippTestZTNA21837 {
    <#
    .SYNOPSIS
    Limit the maximum number of devices per user to 10
    #>
    param($Tenant)

    $TestId = 'ZTNA21837'
    #Tested
    try {
        # Get device registration policy
        $DeviceSettings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DeviceSettings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Limit the maximum number of devices per user to 10' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $UserQuota = $DeviceSettings.userDeviceQuota
        $EntraDeviceSettingsLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/Overview'

        $Passed = 'Failed'
        $CustomStatus = $null

        if ($null -eq $UserQuota -or $UserQuota -le 10) {
            $Passed = 'Passed'
            $ResultMarkdown = "[Maximum number of devices per user]($EntraDeviceSettingsLink) is set to $UserQuota"
        } elseif ($UserQuota -gt 10 -and $UserQuota -le 20) {
            $CustomStatus = 'Investigate'
            $ResultMarkdown = "[Maximum number of devices per user]($EntraDeviceSettingsLink) is set to $UserQuota. Consider reducing to 10 or fewer."
        } else {
            $ResultMarkdown = "[Maximum number of devices per user]($EntraDeviceSettingsLink) is set to $UserQuota. Consider reducing to 10 or fewer."
        }

        if ($CustomStatus) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $CustomStatus -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Limit the maximum number of devices per user to 10' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
        } else {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Limit the maximum number of devices per user to 10' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Limit the maximum number of devices per user to 10' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
    }
}
