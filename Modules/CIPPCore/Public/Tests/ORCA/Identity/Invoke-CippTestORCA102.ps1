function Invoke-CippTestORCA102 {
    <#
    .SYNOPSIS
    Advanced Spam filter options are turned off
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA102' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Advanced Spam filter options are turned off' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $ASFSettings = @(
                $Policy.IncreaseScoreWithImageLinks,
                $Policy.IncreaseScoreWithNumericIps,
                $Policy.IncreaseScoreWithRedirectToOtherPort,
                $Policy.IncreaseScoreWithBizOrInfoUrls,
                $Policy.MarkAsSpamEmptyMessages,
                $Policy.MarkAsSpamJavaScriptInHtml,
                $Policy.MarkAsSpamFramesInHtml,
                $Policy.MarkAsSpamObjectTagsInHtml,
                $Policy.MarkAsSpamEmbedTagsInHtml,
                $Policy.MarkAsSpamFormTagsInHtml,
                $Policy.MarkAsSpamWebBugsInHtml,
                $Policy.MarkAsSpamSensitiveWordList,
                $Policy.MarkAsSpamFromAddressAuthFail,
                $Policy.MarkAsSpamNdrBackscatter,
                $Policy.MarkAsSpamSpfRecordHardFail
            )

            $EnabledASF = $ASFSettings | Where-Object { $_ -eq 'On' }

            if ($EnabledASF.Count -eq 0) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-spam policies have Advanced Spam Filter (ASF) options turned off.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have Advanced Spam Filter (ASF) options enabled.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Enabled ASF Options |`n"
            $Result += "|------------|---------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $EnabledOptions = [System.Collections.Generic.List[string]]::new()
                if ($Policy.IncreaseScoreWithImageLinks -eq 'On') { $EnabledOptions.Add('ImageLinks') | Out-Null }
                if ($Policy.IncreaseScoreWithNumericIps -eq 'On') { $EnabledOptions.Add('NumericIPs') | Out-Null }
                if ($Policy.MarkAsSpamEmptyMessages -eq 'On') { $EnabledOptions.Add('EmptyMessages') | Out-Null }
                if ($Policy.MarkAsSpamJavaScriptInHtml -eq 'On') { $EnabledOptions.Add('JavaScript') | Out-Null }
                $Result += "| $($Policy.Identity) | $($EnabledOptions -join ', ') |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA102' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Advanced Spam filter options are turned off' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA102' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Advanced Spam filter options are turned off' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
