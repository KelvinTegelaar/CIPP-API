function Invoke-CippTestZTNA24552 {
    <#
    .SYNOPSIS
    macOS Firewall policies protect against unauthorized network access
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'macOS Firewall policies protect against unauthorized network access' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $FirewallSettingId = 'com.apple.security.firewall_com.apple.security.firewall'
        $FirewallPolicies = $ConfigurationPolicies.Where({
                $_.platforms -match 'macOS' -and
                $_.technologies -match 'mdm' -and
                $_.technologies -match 'appleRemoteManagement' -and
                $_.settings.settingInstance.settingDefinitionId -contains $FirewallSettingId
            })

        $FirewallRows = foreach ($Policy in $FirewallPolicies) {
            $FirewallSetting = $Policy.settings.settingInstance.Where({ $_.settingDefinitionId -eq $FirewallSettingId }, 'First')[0]
            $Values = @($FirewallSetting.groupSettingCollectionValue)[0].children.choiceSettingValue.value
            [pscustomobject]@{
                Policy   = $Policy
                Enabled  = $Values -contains 'com.apple.security.firewall_enablefirewall_true'
                Assigned = [bool]($Policy.assignments -and $Policy.assignments.Count -gt 0)
            }
        }
        $FirewallRows = @($FirewallRows)

        $ResultLines = [System.Collections.Generic.List[string]]::new()
        if ($FirewallRows.Where({ $_.Enabled -and $_.Assigned }).Count -gt 0) {
            $Status = 'Passed'
            $ResultLines.Add('A macOS firewall policy is configured and assigned in Intune.')
        } else {
            $Status = 'Failed'
            $ResultLines.Add('No assigned macOS firewall policy was found in Intune.')
        }

        if ($FirewallRows.Count -gt 0) {
            $ResultLines.Add('')
            $ResultLines.Add('**macOS Firewall Policies:**')
            $ResultLines.Add('')
            $ResultLines.Add('| Policy Name | Status | Assignment Count | Firewall Status |')
            $ResultLines.Add('| :---------- | :----- | :--------------- | :-------------- |')
            foreach ($Row in $FirewallRows) {
                $PolicyStatus = if ($Row.Assigned) { '✅ Assigned' } else { '❌ Not assigned' }
                $FirewallStatus = if ($Row.Enabled) { '✅ Enabled' } else { '❌ Disabled' }
                $ResultLines.Add("| $($Row.Policy.name) | $PolicyStatus | $(@($Row.Policy.assignments).Count) | $FirewallStatus |")
            }
        }

        $Result = $ResultLines -join "`n"
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'macOS Firewall policies protect against unauthorized network access' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24552' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'macOS Firewall policies protect against unauthorized network access' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Device'
    }
}
