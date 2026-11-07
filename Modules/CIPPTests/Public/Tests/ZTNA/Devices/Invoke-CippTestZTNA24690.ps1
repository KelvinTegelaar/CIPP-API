function Invoke-CippTestZTNA24690 {
    <#
    .SYNOPSIS
    Update policies for macOS are enforced to reduce risk from unpatched vulnerabilities
    #>
    param($Tenant)

    $TestId = 'ZTNA24690'
    $Name = 'Update policies for macOS are enforced to reduce risk from unpatched vulnerabilities'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $DeviceConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $DeviceConfigs -and -not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $MdmPolicies = @($DeviceConfigs).Where({ $_.'@odata.type' -eq '#microsoft.graph.macOSSoftwareUpdateConfiguration' })
        $DdmSettingIds = @('ddm-latestsoftwareupdate_enforcelatestsoftwareupdateversion', 'enforcement_targetosversion')
        $DdmPolicies = @($ConfigurationPolicies).Where({
                $_.platforms -match 'macOS' -and ($_.technologies -match 'mdm' -or $_.technologies -match 'appleRemoteManagement') -and
                @($_.settings.settingInstance.groupSettingCollectionValue.children.settingDefinitionId).Where({ $_ -in $DdmSettingIds }).Count -gt 0
            })
        $UpdatePolicies = @($MdmPolicies) + @($DdmPolicies)
        $Passed = $UpdatePolicies.Where({ @($_.assignments).Count -gt 0 }).Count -gt 0

        $Summary = if ($Passed) { 'At least one macOS update policy is assigned to a group.' } else { 'No macOS update policies are created, or created policies are not assigned.' }
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n")
        if ($UpdatePolicies.Count -gt 0) {
            $null = $ResultMarkdown.Append("## macOS Update Policies`n`n| Policy Name | Status | Assignment Count |`n| :---------- | :----- | :--------------- |`n")
            foreach ($Policy in $UpdatePolicies) {
                $IsMdm = $Policy.'@odata.type' -eq '#microsoft.graph.macOSSoftwareUpdateConfiguration'
                $PolicyName = if ($IsMdm) { $Policy.displayName } else { $Policy.name }
                $PortalLink = if ($IsMdm) { 'https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/iOSiPadOSUpdate' } else { 'https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/configuration' }
                $AssignmentCount = @($Policy.assignments).Count
                $PolicyStatus = if ($AssignmentCount -gt 0) { '✅ Assigned' } else { '❌ Not assigned' }
                $null = $ResultMarkdown.Append("| [$PolicyName]($PortalLink) | $PolicyStatus | $AssignmentCount |`n")
            }
        } else {
            $null = $ResultMarkdown.Append("No macOS update policies found in this tenant.`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
    }
}
