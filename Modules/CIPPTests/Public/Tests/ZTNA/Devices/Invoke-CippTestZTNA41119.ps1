function Invoke-CippTestZTNA41119 {
    <#
    .SYNOPSIS
    Local modification of Microsoft Defender Antivirus policy is blocked
    #>
    param($Tenant)

    $TestId = 'ZTNA41119'
    $Name = 'Local modification of Microsoft Defender Antivirus policy is blocked'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $Policies) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Intune configuration policies found in database. Data collection may not yet have completed.'
            return
        }

        $ControlId = 'device_vendor_msft_defender_configuration_disablelocaladminmerge'
        $TargetNames = @{
            '#microsoft.graph.allDevicesAssignmentTarget'                     = 'allDevices'
            '#microsoft.graph.allLicensedUsersAssignmentTarget'               = 'allLicensedUsers'
            '#microsoft.graph.groupAssignmentTarget'                          = 'groupAssignment'
            '#microsoft.graph.exclusionGroupAssignmentTarget'                 = 'exclusionGroupAssignment'
            '#microsoft.graph.configurationManagerCollectionAssignmentTarget' = 'configurationManagerCollection'
        }

        $Results = foreach ($Policy in $Policies.Where({ $_.technologies -match '(?i)\bmdm\b' })) {
            $Assignments = @($Policy.assignments).Where({ $null -ne $_ })
            $IsAssigned = $Assignments.Count -ge 1
            $Targets = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Assignment in $Assignments) {
                $TargetType = [string]$Assignment.target.'@odata.type'
                [void]$Targets.Add($(if ($TargetNames.ContainsKey($TargetType)) { $TargetNames[$TargetType] } elseif ($TargetType) { ($TargetType -replace '^#microsoft\.graph\.', '') -replace 'AssignmentTarget$', '' } else { 'unknown' }))
            }

            $Instances = @(Get-CippIntuneSettingInstance -Settings $Policy.settings).Where({ [string]$_.settingDefinitionId -ieq $ControlId })
            $RawValues = [System.Collections.Generic.List[string]]::new()
            $States = [System.Collections.Generic.HashSet[string]]::new()
            $InstanceStatuses = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Instance in $Instances) {
                $Value = [string]$Instance.choiceSettingValue.value
                if (-not $RawValues.Contains($Value)) { $RawValues.Add($Value) }
                $State = if ($Value -match '(?i)_disablelocaladminmerge_1$') { 'Enabled' } elseif ($Value -match '(?i)_disablelocaladminmerge_0$') { 'Disabled' } else { 'Unknown' }
                [void]$States.Add($State)
                [void]$InstanceStatuses.Add($(if ($State -eq 'Unknown') { 'Investigate' } elseif ($State -eq 'Disabled') { 'Fail' } elseif ($IsAssigned) { 'Pass' } else { 'Fail' }))
            }

            $Status = if ($Instances.Count -eq 0) { 'N/A' } elseif ($InstanceStatuses.Contains('Fail')) { 'Fail' } elseif ($InstanceStatuses.Contains('Investigate')) { 'Investigate' } else { 'Pass' }
            $Details = switch ($Status) {
                'N/A' { 'The policy does not contain a disable local admin merge setting.' }
                'Pass' { 'Disable local admin merge is set to yes on an assigned policy.' }
                'Investigate' { 'A disable local admin merge value could not be interpreted.' }
                default { if ($States.Contains('Disabled')) { 'Disable local admin merge is set to no.' } else { 'Disable local admin merge is set to yes but the policy is not assigned.' } }
            }

            [PSCustomObject]@{
                PolicyName     = $Policy.name
                PolicyId       = $Policy.id
                TemplateFamily = if ($Policy.templateReference.templateFamily) { $Policy.templateReference.templateFamily } else { 'none' }
                Technologies   = @($Policy.technologies) -join ','
                TemplateId     = $Policy.templateReference.templateId
                Platforms      = @($Policy.platforms) -join ','
                Assigned       = if ($IsAssigned) { 'Yes' } else { 'No' }
                Targets        = if ($Targets.Count -gt 0) { @($Targets) -join ', ' } else { 'None' }
                RawValue       = if ($RawValues.Count -gt 0) { $RawValues -join ', ' } else { 'N/A' }
                State          = if ($States.Count -gt 0) { @($States) -join ', ' } else { 'N/A' }
                Details        = $Details
                Status         = $Status
            }
        }
        $Results = @($Results)
        $Evaluable = $Results.Where({ $_.Status -ne 'N/A' })

        if ($Evaluable.Count -eq 0) {
            $Status = 'Investigate'
            $Result = '⚠️ The **DisableLocalAdminMerge** state could not be determined — no Intune Settings Catalog policy contains the control. Verify the policy in the Intune portal.'
        } elseif ($Evaluable.Where({ $_.Status -eq 'Fail' }).Count -gt 0) {
            $Status = 'Failed'
            $Result = '❌ A retrieved Intune policy sets **DisableLocalAdminMerge** to No (**..._0**), or enables it only in an unassigned policy.'
        } elseif ($Evaluable.Where({ $_.Status -eq 'Investigate' }).Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ The **DisableLocalAdminMerge** state could not be determined — a configured value was uninterpretable. Verify the policy in the Intune portal.'
        } else {
            $Status = 'Passed'
            $Result = '✅ Local modification of Microsoft Defender Antivirus policy is blocked — an assigned Intune Settings Catalog policy sets **DisableLocalAdminMerge** to Yes.'
        }

        if ($Results.Count -gt 0) {
            $StatusDisplay = @{ Pass = '✅ Pass'; Fail = '❌ Fail'; Investigate = '⚠️ Investigate'; 'N/A' = 'N/A' }
            $Result = @(
                $Result
                ''
                '## [Intune configuration profiles](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/configuration)'
                ''
                if ($Results.Count -gt 10) { "Showing first 10 of $($Results.Count) policies" } else { "Total policies: $($Results.Count)" }
                ''
                '| Policy name | Template family | Assigned | Assignment targets | Raw setting value | Normalized state | Details | Status |'
                '| :---------- | :-------------- | :------- | :----------------- | :---------------- | :--------------- | :------ | :----- |'
                foreach ($Row in @($Evaluable; $Results.Where({ $_.Status -eq 'N/A' })).Where({ $true }, 'First', 10)) {
                    $PolicyLink = 'https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/PolicySummaryBlade/policyId/{0}/technology/{1}/templateId/{2}/platformName/{3}' -f $Row.PolicyId, ($Row.Technologies -replace ',', '%2C'), $Row.TemplateId, $Row.Platforms
                    "| [$($Row.PolicyName -replace '\|', '\|')]($PolicyLink) | $($Row.TemplateFamily) | $($Row.Assigned) | $($Row.Targets) | $($Row.RawValue) | $($Row.State) | $($Row.Details) | $($StatusDisplay[$Row.Status]) |"
                }
                if ($Results.Count -gt 10) { "| ... $($Results.Count - 10) omitted; $($Results.Count) total ... | ... | ... | ... | ... | ... | ... | ... |" }
            ) -join "`n"
        }

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
