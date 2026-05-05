function Invoke-CippTestSMB1001_1_10 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.10) - Disable untrusted Microsoft Office macros

    .DESCRIPTION
    Verifies an Attack Surface Reduction (ASR) policy is deployed via Intune that blocks
    Win32 API calls from Office macros and child processes from Office apps. SMB1001 1.10
    (Level 5) requires untrusted Office macros to be disabled.
    #>
    param($Tenant)

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_1_10' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing Intune licenses or data collection not yet completed.' -Risk 'High' -Name 'Untrusted Microsoft Office macros are disabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $ASRPolicies = $ConfigurationPolicies | Where-Object {
            $_.platforms -like '*windows10*' -and
            $_.settings.settingInstance.settingDefinitionId -contains 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
        }

        if (-not $ASRPolicies -or $ASRPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_1_10' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Attack Surface Reduction policies found. ASR rules block Office macro abuse, which SMB1001 1.10 requires.' -Risk 'High' -Name 'Untrusted Microsoft Office macros are disabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $MacroProtected = $ASRPolicies | Where-Object {
            $children = $_.settings.settingInstance.groupSettingCollectionValue.children
            $win32MacroSetting = $children | Where-Object { $_.settingDefinitionId -eq 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros' }
            $officeChildSetting = $children | Where-Object { $_.settingDefinitionId -eq 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses' }
            ($win32MacroSetting.choiceSettingValue.value -like '*_block' -or $win32MacroSetting.choiceSettingValue.value -like '*_warn') -or
            ($officeChildSetting.choiceSettingValue.value -like '*_block' -or $officeChildSetting.choiceSettingValue.value -like '*_warn')
        }

        if (-not $MacroProtected -or $MacroProtected.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_1_10' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'ASR policies exist but none enable the Office macro protection rules (Block Win32 API calls from Office macros / Block Office child processes).' -Risk 'High' -Name 'Untrusted Microsoft Office macros are disabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $Assigned = $MacroProtected | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }

        if ($Assigned.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($Assigned.Count) ASR policy/policies are assigned with Office macro protection rules enabled."
        } else {
            $Status = 'Failed'
            $Result = "ASR policies with Office macro protection exist but are not assigned. Found $($MacroProtected.Count) unassigned policy/policies."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_1_10' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Untrusted Microsoft Office macros are disabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_1_10' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Untrusted Microsoft Office macros are disabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    }
}
