function Invoke-CippTestZTNA24574 {
    <#
    .SYNOPSIS
    Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24574' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $Win10MdmSensePolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*windows10*' -and
            $_.technologies -like '*mdm*' -and
            $_.technologies -like '*microsoftSense*'
        }

        if (-not $Win10MdmSensePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24574' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows ASR policies found' -Risk 'High' -Name 'Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $ASRPolicies = $Win10MdmSensePolicies | Where-Object {
            $settingIds = $_.settings.settingInstance.settingDefinitionId
            $settingIds -contains 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
        }

        if (-not $ASRPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24574' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Attack Surface Reduction policies found' -Risk 'High' -Name 'Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $ObfuscatedScriptPolicies = $ASRPolicies | Where-Object {
            $children = $_.settings.settingInstance.groupSettingCollectionValue.children
            $settingId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutionofpotentiallyobfuscatedscripts'
            $matchingSetting = $children | Where-Object { $_.settingDefinitionId -eq $settingId }
            $value = $matchingSetting.choiceSettingValue.value
            $value -like '*_block' -or $value -like '*_warn'
        }

        $Win32MacroPolicies = $ASRPolicies | Where-Object {
            $children = $_.settings.settingInstance.groupSettingCollectionValue.children
            $settingId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros'
            $matchingSetting = $children | Where-Object { $_.settingDefinitionId -eq $settingId }
            $value = $matchingSetting.choiceSettingValue.value
            $value -like '*_block' -or $value -like '*_warn'
        }

        $AssignedObfuscated = $ObfuscatedScriptPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }
        $AssignedWin32Macro = $Win32MacroPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }

        if ($AssignedObfuscated -and $AssignedWin32Macro) {
            $Status = 'Passed'
            $Result = 'ASR policies are configured and assigned with required rules (obfuscated scripts and Win32 API calls from macros)'
        } elseif ($AssignedObfuscated -or $AssignedWin32Macro) {
            $Status = 'Failed'
            $Result = "ASR policies partially configured. Missing: $(if (-not $AssignedObfuscated) { 'obfuscated scripts rule ' })$(if (-not $AssignedWin32Macro) { 'Win32 API calls rule' })"
        } else {
            $Status = 'Failed'
            $Result = 'ASR policies found but not properly configured or assigned for required rules'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24574' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24574' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Attack Surface Reduction rules are applied to Windows devices to prevent exploitation of vulnerable system components' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Device'
    }
}
