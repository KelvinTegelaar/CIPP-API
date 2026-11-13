function Invoke-CippTestZTNA41052 {
    <#
    .SYNOPSIS
    Application control (WDAC / App Control for Business) is enforced via Intune
    #>
    param($Tenant)

    $TestId = 'ZTNA41052'
    $Name = 'Application control (WDAC / App Control for Business) is enforced via Intune'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'High'; Category = 'Endpoint threat protection' }

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

        $PolicyResults = foreach ($Policy in $Policies.Where({ $_.templateReference.templateFamily -eq 'endpointSecurityApplicationControl' })) {
            $Mode = 'Unknown'
            $BuildOptions = @($Policy.settings).Where({
                    $_.settingInstance.settingDefinitionId -match '(?i)device_vendor_msft_policy_config_applicationcontrol' -and
                    $_.settingInstance.choiceSettingValue.value -match '(?i)_(built_in_controls|configure_xml|upload_xml)_selected$'
                })
            if ($BuildOptions.Count -eq 1) {
                $BuildOption = $BuildOptions[0].settingInstance
                $Pending = [System.Collections.Generic.Queue[object]]::new()
                foreach ($Child in @($BuildOption.choiceSettingValue.children)) { if ($null -ne $Child) { $Pending.Enqueue($Child) } }
                $IsBuiltIn = [string]$BuildOption.choiceSettingValue.value -match '(?i)_built_in_controls_selected$'
                $Modes = [System.Collections.Generic.HashSet[string]]::new()
                while ($Pending.Count -gt 0) {
                    $Instance = $Pending.Dequeue()
                    $SettingId = [string]$Instance.settingDefinitionId
                    if ($IsBuiltIn) {
                        if ($SettingId -eq 'device_vendor_msft_policy_config_applicationcontrol_enable_app_control') {
                            switch ([string]$Instance.choiceSettingValue.value) {
                                'device_vendor_msft_policy_config_applicationcontrol_enable_app_control_audit_only' { [void]$Modes.Add('Audit') }
                                'device_vendor_msft_policy_config_applicationcontrol_enable_app_control_enabled' { [void]$Modes.Add('Enforce') }
                            }
                        }
                    } elseif ($SettingId -match '(?i)applicationcontrol' -and -not [string]::IsNullOrWhiteSpace([string]$Instance.simpleSettingValue.value)) {
                        $XmlValue = [string]$Instance.simpleSettingValue.value
                        $Candidates = [System.Collections.Generic.List[string]]::new()
                        $Candidates.Add($XmlValue)
                        try {
                            $Bytes = [Convert]::FromBase64String($XmlValue)
                            $Candidates.Add([Text.Encoding]::UTF8.GetString($Bytes))
                            $Candidates.Add([Text.Encoding]::Unicode.GetString($Bytes))
                            $Candidates.Add([Text.Encoding]::BigEndianUnicode.GetString($Bytes))
                        } catch {
                            Write-Verbose 'App Control policy XML is not Base64 encoded'
                        }
                        foreach ($Candidate in $Candidates) {
                            try {
                                $PolicyXml = [xml]$Candidate
                            } catch {
                                continue
                            }
                            if ($PolicyXml.DocumentElement.LocalName -ne 'SiPolicy') { continue }
                            $PolicyType = $PolicyXml.SelectSingleNode("//*[local-name()='PolicyType']")
                            if ($null -eq $PolicyType -or $PolicyType.InnerText.Trim() -ne 'Base Policy') { continue }
                            $IsAudit = @($PolicyXml.SelectNodes("//*[local-name()='Option']")).Where({ $_.InnerText.Trim() -eq 'Enabled:Audit Mode' }).Count -gt 0
                            [void]$Modes.Add($(if ($IsAudit) { 'Audit' } else { 'Enforce' }))
                            break
                        }
                    }
                    foreach ($Child in @($Instance.choiceSettingValue.children)) { if ($null -ne $Child) { $Pending.Enqueue($Child) } }
                }
                if ($Modes.Count -eq 1) { $Mode = @($Modes)[0] }
            }

            $AssignmentCount = [int]$Policy.assignments.Count
            [PSCustomObject]@{
                Name            = $Policy.name
                PolicyId        = $Policy.id
                Technologies    = @($Policy.technologies) -join ','
                TemplateId      = $Policy.templateReference.templateId
                Platforms       = $Policy.platforms
                Mode            = $Mode
                AssignmentCount = $AssignmentCount
                LastModified    = $Policy.lastModifiedDateTime
                Status          = if ($AssignmentCount -eq 0) { 'Fail' } elseif ($Mode -eq 'Enforce') { 'Pass' } elseif ($Mode -eq 'Unknown') { 'Investigate' } else { 'Fail' }
            }
        }
        $PolicyResults = @($PolicyResults)

        if ($PolicyResults.Where({ $_.Status -eq 'Pass' }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ An App Control for Business policy is configured, enforced, and assigned in Microsoft Intune.'
        } elseif ($PolicyResults.Where({ $_.Status -eq 'Investigate' }).Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ An App Control for Business policy was returned, but its enforcement mode could not be determined from the returned data.'
        } else {
            $Status = 'Failed'
            $Result = '❌ No App Control for Business policies were returned, no policies are assigned, or all assigned policies are audit-only.'
        }

        $Result = @(
            $Result
            ''
            '## [Intune App Control for Business](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/appControl)'
            ''
            '| Policy Name | Mode | Assignment State | Assignment Count | Last Modified | Status |'
            '| :---------- | :--- | :--------------- | ---------------: | :------------ | :----- |'
            if ($PolicyResults.Count -eq 0) { '| No App Control for Business policies found | — | — | 0 | — | Fail |' }
            foreach ($Row in $PolicyResults.Where({ $true }, 'First', 10)) {
                $PolicyLink = 'https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/PolicySummaryBlade/policyId/{0}/technology/{1}/templateId/{2}/platformName/{3}' -f $Row.PolicyId, ($Row.Technologies -replace ',', '%2C'), $Row.TemplateId, $Row.Platforms
                $AssignmentState = if ($Row.AssignmentCount -gt 0) { 'Assigned' } else { 'Unassigned' }
                "| [$($Row.Name -replace '\|', '\|')]($PolicyLink) | $($Row.Mode) | $AssignmentState | $($Row.AssignmentCount) | $($Row.LastModified) | $($Row.Status) |"
            }
            if ($PolicyResults.Count -gt 10) { "| ... | | | | | $($PolicyResults.Count) total policies |" }
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
