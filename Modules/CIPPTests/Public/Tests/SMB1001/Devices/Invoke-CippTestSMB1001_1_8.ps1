function Invoke-CippTestSMB1001_1_8 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.8) - Ensure important digital data is encrypted at rest

    .DESCRIPTION
    Verifies BitLocker encryption is enforced on Windows devices via an Intune configuration
    policy. SMB1001 1.8 (Level 5) requires data at rest to be encrypted on devices that store
    sensitive information. Detection follows the ZTNA24550 pattern — looks for the
    'device_vendor_msft_bitlocker_requiredeviceencryption_1' setting value on Windows
    configuration policies.
    #>
    param($Tenant)

    $TestId = 'SMB1001_1_8'
    $Name = 'Important digital data is encrypted at rest'

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'IntuneConfigurationPolicies cache not found. This may be due to missing Intune licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $WindowsPolicies = $ConfigurationPolicies | Where-Object { $_.platforms -match 'windows10' }

        $WindowsBitLockerPolicies = @(
            foreach ($Policy in $WindowsPolicies) {
                $ValidSettingValues = @('device_vendor_msft_bitlocker_requiredeviceencryption_1')

                if ($Policy.settings.settinginstance.choicesettingvalue.value) {
                    $PolicySettingValues = $Policy.settings.settinginstance.choicesettingvalue.value
                    if ($PolicySettingValues -isnot [array]) {
                        $PolicySettingValues = @($PolicySettingValues)
                    }

                    foreach ($SettingValue in $PolicySettingValues) {
                        if ($ValidSettingValues -contains $SettingValue) {
                            $Policy
                            break
                        }
                    }
                }
            }
        )

        $AssignedPolicies = @($WindowsBitLockerPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $TableRows = foreach ($Policy in $WindowsBitLockerPolicies) {
                $PolicyStatus = if ($Policy.assignments -and $Policy.assignments.Count -gt 0) { '✅ Assigned' } else { '❌ Not assigned' }
                $AssignmentCount = if ($Policy.assignments) { $Policy.assignments.Count } else { 0 }
                "| $($Policy.name) | $PolicyStatus | $AssignmentCount |"
            }
            $Result = (@(
                    'At least one Windows BitLocker policy is configured and assigned.'
                    ''
                    '**Windows BitLocker Policies:**'
                    ''
                    '| Policy Name | Status | Assignment Count |'
                    '| :---------- | :----- | :--------------- |'
                ) + $TableRows) -join "`n"
        } else {
            $Status = 'Failed'
            if ($WindowsBitLockerPolicies.Count -gt 0) {
                $UnassignedRows = foreach ($Policy in $WindowsBitLockerPolicies) { "- $($Policy.name)" }
                $Result = (@(
                        'Windows BitLocker policies exist but none are assigned.'
                        ''
                        '**Unassigned BitLocker Policies:**'
                        ''
                    ) + $UnassignedRows) -join "`n"
            } else {
                $Result = 'No Windows BitLocker policy is configured.'
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
