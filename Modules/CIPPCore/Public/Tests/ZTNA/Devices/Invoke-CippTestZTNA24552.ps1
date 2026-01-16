function Invoke-CippTestZTNA24552 {
    <#
    .SYNOPSIS
    Data on macOS is protected by firewall
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigurationPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on macOS is protected by firewall' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $MacOSPolicies = $ConfigurationPolicies | Where-Object {
            $_.platforms -match 'macOS'
        }

        $MacOSFirewallPolicies = @()
        foreach ($MacOSPolicy in $MacOSPolicies) {
            $ValidSettingValues = @('com.apple.security.firewall_enablefirewall_true')

            if ($MacOSPolicy.settings.settinginstance.choicesettingvalue.value) {
                $PolicySettingValues = $MacOSPolicy.settings.settinginstance.choicesettingvalue.value
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
                    $MacOSFirewallPolicies += $MacOSPolicy
                }
            }
        }

        $AssignedPolicies = $MacOSFirewallPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $ResultLines = @(
                'At least one macOS Firewall policy is configured and assigned.'
                ''
                '**macOS Firewall Policies:**'
                ''
                '| Policy Name | Status | Assignment Count |'
                '| :---------- | :----- | :--------------- |'
            )

            foreach ($Policy in $MacOSFirewallPolicies) {
                $PolicyStatus = if ($Policy.assignments -and $Policy.assignments.Count -gt 0) {
                    '✅ Assigned'
                } else {
                    '❌ Not assigned'
                }
                $AssignmentCount = if ($Policy.assignments) { $Policy.assignments.Count } else { 0 }
                $ResultLines += "| $($Policy.name) | $PolicyStatus | $AssignmentCount |"
            }

            $Result = $ResultLines -join "`n"
        } else {
            $Status = 'Failed'
            if ($MacOSFirewallPolicies.Count -gt 0) {
                $ResultLines = @(
                    'macOS Firewall policies exist but none are assigned.'
                    ''
                    '**Unassigned Firewall Policies:**'
                    ''
                )
                foreach ($Policy in $MacOSFirewallPolicies) {
                    $ResultLines += "- $($Policy.name)"
                }
            } else {
                $ResultLines = @('No macOS Firewall policy is configured or assigned.')
            }
            $Result = $ResultLines -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Data on macOS is protected by firewall' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on macOS is protected by firewall' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
