function Invoke-CippTestZTNA24802 {
    <#
    .SYNOPSIS
    Device cleanup rules maintain tenant hygiene by hiding inactive devices
    #>
    param($Tenant)

    $TestId = 'ZTNA24802'
    $Name = 'Device cleanup rules maintain tenant hygiene by hiding inactive devices'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'Low' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $CleanupRules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDeviceCleanupRules').Where({ $null -ne $_ })
        if ($CleanupRules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ManagedDeviceCleanupRules' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. Device clean-up rules have not been collected yet.' -Risk 'Low' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        if ($CleanupRules.Count -gt 0) {
            $Status = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("At least one device clean-up rule exists.`n`n## Device clean-up rules`n`n| Rule Name | Platform or OS |`n| :-------- | :------------- |`n")
            foreach ($Rule in $CleanupRules) {
                $null = $ResultMarkdown.Append("| [$($Rule.displayName)](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/deviceCleanUp) | $($Rule.deviceCleanupRulePlatformType) |`n")
            }
        } else {
            $Status = 'Failed'
            $ResultMarkdown = 'No device clean-up rule exists.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'Low' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
