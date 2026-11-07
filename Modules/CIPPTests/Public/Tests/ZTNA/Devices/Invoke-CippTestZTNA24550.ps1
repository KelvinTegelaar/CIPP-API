function Invoke-CippTestZTNA24550 {
    <#
    .SYNOPSIS
    Data on Windows is protected by BitLocker encryption
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        $DeviceConfigs = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'
        if (-not $ConfigurationPolicies -and -not $DeviceConfigs) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $BitLockerPolicies = foreach ($Policy in @($ConfigurationPolicies).Where({ $_.platforms -match 'windows10' })) {
            $Stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($Instance in @($Policy.settings.settingInstance)) { if ($Instance) { $Stack.Push($Instance) } }
            while ($Stack.Count -gt 0) {
                $Instance = $Stack.Pop()
                if ($Instance.choiceSettingValue.value -eq 'device_vendor_msft_bitlocker_requiredeviceencryption_1') {
                    $Policy
                    break
                }
                foreach ($Child in @($Instance.groupSettingCollectionValue.children; $Instance.groupSettingValue.children; $Instance.choiceSettingValue.children; $Instance.choiceSettingCollectionValue.children)) {
                    if ($Child) { $Stack.Push($Child) }
                }
            }
        }
        $BitLockerPolicies = @($BitLockerPolicies)

        # Graph returns the bitLocker*DrivePolicy objects on every endpoint protection profile, so only the explicit switches mean BitLocker is enforced.
        $LegacyProfiles = @(@($DeviceConfigs).Where({
                    $_.'@odata.type' -in @('#microsoft.graph.windows10EndpointProtectionConfiguration', '#microsoft.graph.windows10GeneralConfiguration') -and
                    ($_.storageRequireDeviceEncryption -eq $true -or $_.bitLockerEncryptDevice -eq $true)
                }))

        $Assigned = @($BitLockerPolicies; $LegacyProfiles).Where({ $_.assignments -and $_.assignments.Count -gt 0 })

        $ResultLines = [System.Collections.Generic.List[string]]::new()
        if ($Assigned.Count -gt 0) {
            $Status = 'Passed'
            $ResultLines.Add('At least one Windows BitLocker policy is configured and assigned.')
        } else {
            $Status = 'Failed'
            $ResultLines.Add('No Windows BitLocker policy is configured or assigned.')
        }

        if ($BitLockerPolicies.Count -gt 0) {
            $ResultLines.Add('')
            $ResultLines.Add('**Windows BitLocker Policies:**')
            $ResultLines.Add('')
            $ResultLines.Add('| Policy Name | Template Family | Status | Assignment Count |')
            $ResultLines.Add('| :---------- | :-------------- | :----- | :--------------- |')
            foreach ($Policy in $BitLockerPolicies) {
                $PolicyStatus = if ($Policy.assignments -and $Policy.assignments.Count -gt 0) { '✅ Assigned' } else { '❌ Not assigned' }
                $ResultLines.Add("| $($Policy.name) | $($Policy.templateReference.templateFamily) | $PolicyStatus | $(@($Policy.assignments).Count) |")
            }
        }

        if ($LegacyProfiles.Count -gt 0) {
            $ResultLines.Add('')
            $ResultLines.Add('**Legacy Windows BitLocker Profiles:**')
            $ResultLines.Add('')
            $ResultLines.Add('| Profile Name | Profile Type | Status | Assignment Count |')
            $ResultLines.Add('| :----------- | :----------- | :----- | :--------------- |')
            foreach ($LegacyProfile in $LegacyProfiles) {
                $PolicyStatus = if ($LegacyProfile.assignments -and $LegacyProfile.assignments.Count -gt 0) { '✅ Assigned' } else { '❌ Not assigned' }
                $ProfileType = $LegacyProfile.'@odata.type' -replace '#microsoft.graph.', ''
                $ResultLines.Add("| $($LegacyProfile.displayName) | $ProfileType | $PolicyStatus | $(@($LegacyProfile.assignments).Count) |")
            }
        }

        $Result = $ResultLines -join "`n"
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
