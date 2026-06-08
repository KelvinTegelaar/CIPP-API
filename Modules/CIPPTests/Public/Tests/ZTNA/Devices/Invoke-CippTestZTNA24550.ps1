function Invoke-CippTestZTNA24550 {
    <#
    .SYNOPSIS
    Data on Windows is protected by BitLocker encryption
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $WindowsPolicies = $ConfigurationPolicies | Where-Object {
            $_.platforms -match 'windows10'
        }

        $WindowsBitLockerPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($WindowsPolicy in $WindowsPolicies) {
            $ValidSettingValues = @('device_vendor_msft_bitlocker_requiredeviceencryption_1')

            if ($WindowsPolicy.settings.settinginstance.choicesettingvalue.value) {
                $PolicySettingValues = $WindowsPolicy.settings.settinginstance.choicesettingvalue.value
                if ($PolicySettingValues -isnot [array]) {
                    $PolicySettingValues = @($PolicySettingValues)
                }

                $HasValidSetting = $false
                foreach ($SettingValue in $PolicySettingValues) {
                    if ($ValidSettingValues -contains $SettingValue) {
                        $HasValidSetting = $true
                        break
                    }
                }

                if ($HasValidSetting) {
                    $WindowsBitLockerPolicies.Add($WindowsPolicy)
                }
            }
        }

        $AssignedPolicies = $WindowsBitLockerPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $ResultLines = [System.Collections.Generic.List[string]]::new()
            $ResultLines.Add('At least one Windows BitLocker policy is configured and assigned.')
            $ResultLines.Add('')
            $ResultLines.Add('**Windows BitLocker Policies:**')
            $ResultLines.Add('')
            $ResultLines.Add('| Policy Name | Status | Assignment Count |')
            $ResultLines.Add('| :---------- | :----- | :--------------- |')

            foreach ($Policy in $WindowsBitLockerPolicies) {
                $PolicyStatus = if ($Policy.assignments -and $Policy.assignments.Count -gt 0) {
                    '✅ Assigned'
                } else {
                    '❌ Not assigned'
                }
                $AssignmentCount = if ($Policy.assignments) { $Policy.assignments.Count } else { 0 }
                $ResultLines.Add("| $($Policy.name) | $PolicyStatus | $AssignmentCount |")
            }

            $Result = $ResultLines -join "`n"
        } else {
            $Status = 'Failed'
            if ($WindowsBitLockerPolicies.Count -gt 0) {
                $ResultLines = [System.Collections.Generic.List[string]]::new()
                $ResultLines.Add('Windows BitLocker policies exist but none are assigned.')
                $ResultLines.Add('')
                $ResultLines.Add('**Unassigned BitLocker Policies:**')
                $ResultLines.Add('')
                foreach ($Policy in $WindowsBitLockerPolicies) {
                    $ResultLines.Add("- $($Policy.name)")
                }
            } else {
                $ResultLines = @('No Windows BitLocker policy is configured or assigned.')
            }
            $Result = $ResultLines -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24550' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on Windows is protected by BitLocker encryption' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
