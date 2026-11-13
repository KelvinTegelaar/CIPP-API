function Invoke-CippTestZTNA24551 {
    <#
    .SYNOPSIS
    Authentication on Windows uses Windows Hello for Business
    #>
    param($Tenant)

    $TestId = 'ZTNA24551'
    $Name = 'Authentication on Windows uses Windows Hello for Business'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $EnrollmentConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceEnrollmentConfigurations'
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $EnrollmentConfigs -and -not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $TenantConfigs = @($EnrollmentConfigs).Where({ $_.deviceEnrollmentConfigurationType -eq 'windowsHelloForBusiness' })
        $WhfbSettingIds = @('device_vendor_msft_passportforwork_{tenantid}_policies_usepassportforwork', 'user_vendor_msft_passportforwork_{tenantid}_policies_usepassportforwork')
        $WhfbPolicies = @($ConfigurationPolicies).Where({
                $_.platforms -match 'windows10' -and $_.technologies -match 'mdm' -and
                @($_.settings.settingInstance.groupSettingCollectionValue.children.settingDefinitionId).Where({ $_ -in $WhfbSettingIds }).Count -gt 0
            })

        $TenantEnabled = $TenantConfigs.Where({ $_.state -eq 'enabled' }).Count -gt 0
        $Passed = $TenantEnabled -or $WhfbPolicies.Where({ @($_.assignments).Count -gt 0 }).Count -gt 0

        $Summary = if ($Passed) { 'Windows Hello for Business policy is assigned and enforced.' } else { 'Windows Hello for Business policy is not assigned or not enforced.' }
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n## Windows Hello for Business Policy is Configured and Assigned`n`n")
        if ($TenantConfigs.Count -gt 0) {
            $TenantState = if ($TenantEnabled) { '✅ Enabled' } elseif ($TenantConfigs.Where({ $_.state -eq 'disabled' }).Count -gt 0) { '❌ Disabled' } else { '❓ Not Configured' }
            $null = $ResultMarkdown.Append("Windows Hello For Business ([Tenant Wide Setting](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesEnrollmentMenu/~/windowsEnrollment)): $TenantState.`n`n")
        }
        if ($WhfbPolicies.Count -gt 0) {
            $null = $ResultMarkdown.Append("| Policy Name | Status | Assignment Count |`n| :---------- | :----- | :--------------- |`n")
            foreach ($Policy in $WhfbPolicies) {
                $AssignmentCount = @($Policy.assignments).Count
                $PolicyStatus = if ($AssignmentCount -gt 0) { '✅ Assigned' } else { '❌ Not assigned' }
                $null = $ResultMarkdown.Append("| [$($Policy.name)](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/configuration) | $PolicyStatus | $AssignmentCount |`n")
            }
        } else {
            $null = $ResultMarkdown.Append("No Windows Hello for Business configuration policies found.`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    }
}
