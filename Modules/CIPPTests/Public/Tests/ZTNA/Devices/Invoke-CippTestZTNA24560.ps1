function Invoke-CippTestZTNA24560 {
    <#
    .SYNOPSIS
    Local administrator credentials on Windows are protected by Windows LAPS
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24560' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Local administrator credentials on Windows are protected by Windows LAPS' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $WindowsPolicies = $ConfigPolicies | Where-Object {
            $_.templateReference.templateFamily -eq 'endpointSecurityAccountProtection' -and
            $_.platforms -like '*windows10*'
        }

        if (-not $WindowsPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24560' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows LAPS policies found' -Risk 'High' -Name 'Local administrator credentials on Windows are protected by Windows LAPS' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $LapsPolicies = $WindowsPolicies | Where-Object {
            $settingIds = $_.settings.settingInstance.settingDefinitionId
            $settingIds -contains 'device_vendor_msft_laps_policies_backupdirectory' -or
            $settingIds -contains 'device_vendor_msft_laps_policies_automaticaccountmanagementenabled'
        }

        if (-not $LapsPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24560' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No LAPS policies configured' -Risk 'High' -Name 'Local administrator credentials on Windows are protected by Windows LAPS' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $CompliantPolicies = $LapsPolicies | Where-Object {
            $settingIds = $_.settings.settingInstance.settingDefinitionId
            $choiceValues = $_.settings.settingInstance.choiceSettingValue.value

            $hasBackupDir = $settingIds -contains 'device_vendor_msft_laps_policies_backupdirectory'
            $hasEntraBackup = $choiceValues -contains 'device_vendor_msft_laps_policies_backupdirectory_1'
            $hasAdBackup = $choiceValues -contains 'device_vendor_msft_laps_policies_backupdirectory_2'
            $hasAutoMgmt = $choiceValues -contains 'device_vendor_msft_laps_policies_automaticaccountmanagementenabled_true'

            ($hasBackupDir -and ($hasEntraBackup -or $hasAdBackup) -and $hasAutoMgmt)
        }

        $AssignedCompliantPolicies = $CompliantPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedCompliantPolicies) {
            $Status = 'Passed'
            $Result = "Cloud LAPS policy is assigned and enforced. Found $($AssignedCompliantPolicies.Count) compliant and assigned policy/policies"
        } else {
            $Status = 'Failed'
            if ($CompliantPolicies) {
                $Result = "Cloud LAPS policy exists but is not assigned. Found $($CompliantPolicies.Count) compliant but unassigned policy/policies"
            } else {
                $Result = 'Cloud LAPS policy is not configured correctly or not enforced'
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24560' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Local administrator credentials on Windows are protected by Windows LAPS' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24560' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Local administrator credentials on Windows are protected by Windows LAPS' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
