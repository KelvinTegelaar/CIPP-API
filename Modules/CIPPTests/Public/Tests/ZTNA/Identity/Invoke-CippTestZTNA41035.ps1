function Invoke-CippTestZTNA41035 {
    <#
    .SYNOPSIS
    User reporting for phishing and spam is enabled and routed to a reviewed mailbox
    #>
    param($Tenant)

    $TestId = 'ZTNA41035'
    $Name = 'User reporting for phishing and spam is enabled and routed to a reviewed mailbox'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Exchange -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policy = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ReportSubmissionPolicy')[0]
        if ($null -eq $Policy) {
            if (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ReportSubmissionPolicy' -CountsOnly) {
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown '⚠️ **Get-ReportSubmissionPolicy** returned no results. In an unconfigured tenant the policy object is not created until user-reported settings are explicitly saved — the effective defaults cannot be confirmed from PowerShell. Verify the configuration in the [Defender portal > User reported settings](https://security.microsoft.com/securitysettings/userSubmission) and re-run after saving the settings.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'The report submission policy has not been collected for this tenant. Refresh the ReportSubmissionPolicy cache.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            }
            return
        }
        $Rule = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ReportSubmissionRule')[0]

        $MicrosoftRoute = $Policy.EnableReportToMicrosoft -eq $true
        $JunkFlag = $Policy.ReportJunkToCustomizedAddress -eq $true
        $NotJunkFlag = $Policy.ReportNotJunkToCustomizedAddress -eq $true
        $PhishFlag = $Policy.ReportPhishToCustomizedAddress -eq $true
        $JunkCount = @($Policy.ReportJunkAddresses).Where({ $_ }).Count
        $NotJunkCount = @($Policy.ReportNotJunkAddresses).Where({ $_ }).Count
        $PhishCount = @($Policy.ReportPhishAddresses).Where({ $_ }).Count

        $CustomComplete = $JunkFlag -and $NotJunkFlag -and $PhishFlag -and $JunkCount -gt 0 -and $NotJunkCount -gt 0 -and $PhishCount -gt 0
        $CustomPartial = ($JunkFlag -or $NotJunkFlag -or $PhishFlag -or $JunkCount -gt 0 -or $NotJunkCount -gt 0 -or $PhishCount -gt 0) -and -not $CustomComplete
        $SentTo = @($Rule.SentTo).Where({ -not [string]::IsNullOrWhiteSpace([string]$_) })
        $RuleActionable = $null -ne $Rule -and $Rule.State -eq 'Enabled' -and $SentTo.Count -gt 0
        $CustomRoute = $CustomComplete -and $RuleActionable
        $CustomRuleProblem = $CustomComplete -and -not $RuleActionable

        $ThirdPartyCount = @($Policy.ThirdPartyReportAddresses).Where({ $_ }).Count
        $ThirdPartyConfigured = $Policy.EnableThirdPartyAddress -eq $true -and $ThirdPartyCount -gt 0
        $ThirdPartyAttempted = $Policy.EnableThirdPartyAddress -eq $true -or $ThirdPartyCount -gt 0
        $ThirdPartyPartial = $ThirdPartyAttempted -and -not $ThirdPartyConfigured
        $ThirdPartyRoute = $ThirdPartyConfigured -and $RuleActionable
        $ThirdPartyRuleProblem = $ThirdPartyConfigured -and -not $RuleActionable

        $AnyRoute = $MicrosoftRoute -or $CustomRoute -or $ThirdPartyRoute
        $RuleProblem = if ($null -eq $Rule) { 'no report submission rule exists' } elseif ($Rule.State -eq 'Disabled') { "report submission rule '**$(ConvertTo-CippMarkdownCell $Rule.Name)**' is **Disabled**" } else { "report submission rule '**$(ConvertTo-CippMarkdownCell $Rule.Name)**' has no **SentTo** address" }

        if ($AnyRoute) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ User reporting in Outlook is enabled and user-reported messages reach Microsoft, a monitored SOC mailbox, or a configured non-Microsoft reporter.')
        } elseif ($CustomPartial -or $CustomRuleProblem -or $ThirdPartyRuleProblem) {
            $Status = 'Investigate'
            $Details = @(
                if ($CustomPartial) { '- custom reporting mailbox is partially configured — only some of **ReportJunkToCustomizedAddress**/**ReportNotJunkToCustomizedAddress**/**ReportPhishToCustomizedAddress** routing flags or **ReportJunkAddresses**/**ReportNotJunkAddresses**/**ReportPhishAddresses** address lists are set; all six must be configured' }
                if ($CustomRuleProblem) { "- all three custom-mailbox flags and address lists are configured but $RuleProblem — nothing delivers messages to the SOC mailbox" }
                if ($ThirdPartyRuleProblem) { "- **EnableThirdPartyAddress** and **ThirdPartyReportAddresses** are configured but $RuleProblem — nothing delivers non-Microsoft reporter messages to the reporting mailbox" }
            )
            $Result = [System.Text.StringBuilder]::new("⚠️ The customized mailbox is partially configured, the report submission rule is absent or disabled, or the non-Microsoft reporter route is incomplete; verify the configuration in the Defender portal.`n`n$($Details -join "`n")")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("❌ Reports are sent nowhere actionable; the SOC has no visibility into what end users are reporting and Microsoft re-evaluation is not in the loop.`n`n> **Note:** If your organization uses a non-Microsoft reporting button (such as KnowBe4 PAB or Cofense Reporter) that does not integrate with Exchange Online's report submission policy, this result may be a false positive — verify whether a third-party reporter is in use before remediating.")
        }

        $CustomNA = $AnyRoute -and -not $CustomComplete -and -not $CustomPartial
        $CustomResult = if ($CustomRoute) { '✅ Pass' } elseif ($CustomPartial -or $CustomRuleProblem) { '⚠️ Investigate' } elseif ($CustomNA) { 'N/A' } else { '❌ Fail' }
        $ThirdPartyResult = if ($ThirdPartyRoute) { '✅ Pass' } elseif ($ThirdPartyRuleProblem -or $ThirdPartyPartial) { '⚠️ Investigate' } elseif ($AnyRoute -and -not $ThirdPartyAttempted) { 'N/A' } else { '❌ Fail' }
        $RuleRelevant = $CustomComplete -or $ThirdPartyConfigured
        $RuleResult = if (-not $RuleRelevant) { 'N/A' } elseif ($RuleActionable) { '✅ Pass' } else { '⚠️ Investigate' }
        $RuleState = if (-not $RuleRelevant -or $null -eq $Rule) { '—' } else { "``$($Rule.State)``" }
        $RuleSentTo = if (-not $RuleRelevant -or $SentTo.Count -eq 0) { '—' } else { ConvertTo-CippMarkdownCell ($SentTo -join ', ') }

        $Rows = @(
            ,@('EnableReportToMicrosoft', $Policy.EnableReportToMicrosoft, 'True (re-evaluation + model training)', $(if ($MicrosoftRoute) { '✅ Pass' } else { '❌ Fail' }))
            ,@('ReportJunkToCustomizedAddress', $Policy.ReportJunkToCustomizedAddress, 'True (custom SOC mailbox route)', $CustomResult)
            ,@('ReportNotJunkToCustomizedAddress', $Policy.ReportNotJunkToCustomizedAddress, 'True (custom SOC mailbox route)', $CustomResult)
            ,@('ReportPhishToCustomizedAddress', $Policy.ReportPhishToCustomizedAddress, 'True (custom SOC mailbox route)', $CustomResult)
            ,@('ReportJunkAddresses', $Policy.ReportJunkAddresses, 'non-empty (custom SOC mailbox)', $CustomResult)
            ,@('ReportNotJunkAddresses', $Policy.ReportNotJunkAddresses, 'non-empty (custom SOC mailbox)', $CustomResult)
            ,@('ReportPhishAddresses', $Policy.ReportPhishAddresses, 'non-empty (custom SOC mailbox)', $CustomResult)
            ,@('EnableThirdPartyAddress', $Policy.EnableThirdPartyAddress, 'True (if using non-Microsoft reporter)', $ThirdPartyResult)
            ,@('ThirdPartyReportAddresses', $Policy.ThirdPartyReportAddresses, 'non-empty (if using non-Microsoft reporter)', $ThirdPartyResult)
            ,@('ReportChatMessageEnabled', $Policy.ReportChatMessageEnabled, 'True (MDO P2 + Teams policy required)', 'ℹ️ Informational')
            ,@('PostSubmitMessageEnabled', $Policy.PostSubmitMessageEnabled, 'True (user feedback after submission)', 'ℹ️ Informational')
        )
        $null = $Result.Append("`n`n## [User reported settings](https://security.microsoft.com/userSubmissionsReportMessage)`n`n")
        $null = $Result.Append("| Setting | Value | Recommended | Result |`n")
        $null = $Result.Append("| :------ | :---- | :---------- | :----- |`n")
        foreach ($Row in $Rows) {
            $Values = @($Row[1]).Where({ $null -ne $_ -and "$_" -ne '' })
            $Value = if ($Values.Count -eq 0) { '—' } elseif ($Values.Count -gt 3) { "$(ConvertTo-CippMarkdownCell ($Values.Where({ $true }, 'First', 3) -join ', ')) *(+$($Values.Count - 3) more)*" } else { ConvertTo-CippMarkdownCell ($Values -join ', ') }
            $null = $Result.Append("| $($Row[0]) | $Value | $($Row[2]) | $($Row[3]) |`n")
        }
        $null = $Result.Append("| Report submission rule State | $RuleState | Enabled | $RuleResult |`n")
        $null = $Result.Append("| Report submission rule SentTo | $RuleSentTo | (SOC mailbox address) | $RuleResult |`n")

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
