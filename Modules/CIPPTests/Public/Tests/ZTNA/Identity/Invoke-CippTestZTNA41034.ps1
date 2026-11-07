function Invoke-CippTestZTNA41034 {
    <#
    .SYNOPSIS
    Anti-spam (hosted content filter) policies are configured with recommended thresholds and actions
    #>
    param($Tenant)

    $TestId = 'ZTNA41034'
    $Name = 'Anti-spam (hosted content filter) policies are configured with recommended thresholds and actions'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Exchange -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy').Where({ $null -ne $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterRule').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -or ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoHostedContentFilterRule' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Anti-spam policies or rules have not been collected for this tenant. Refresh the ExoHostedContentFilterPolicy and ExoHostedContentFilterRule caches.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }
        $DefaultPolicy = $Policies.Where({ $_.IsDefault -eq $true }, 'First')[0]
        if ($null -eq $DefaultPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown '⚠️ Policies were returned by **Get-HostedContentFilterPolicy** but none has **IsDefault = $true**. The Default policy is always present in Exchange Online; this indicates unexpected data — refresh the cache and re-run.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $PolicyByIdentity = @{}
        foreach ($Policy in $Policies) { $PolicyByIdentity[[string]$Policy.Identity] = $Policy }
        $RulesForPolicy = @{}
        foreach ($Rule in $Rules.Where({ $_.State -eq 'Enabled' })) {
            $Key = [string]$Rule.HostedContentFilterPolicy
            if (-not $RulesForPolicy.ContainsKey($Key)) { $RulesForPolicy[$Key] = [System.Collections.Generic.List[string]]::new() }
            $RulesForPolicy[$Key].Add([string]$Rule.Name)
        }
        $InScopeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $null = $InScopeIds.Add([string]$DefaultPolicy.Identity)
        foreach ($Id in $RulesForPolicy.Keys) { $null = $InScopeIds.Add($Id) }

        $Passed = $true
        $HasInvestigate = $false
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $InScopeIds) {
            $Policy = $PolicyByIdentity[$Id]
            $RuleNames = if ($RulesForPolicy.ContainsKey($Id)) { $RulesForPolicy[$Id] -join ', ' } else { '' }
            if ($null -eq $Policy) {
                $HasInvestigate = $true
                $Rows.Add([pscustomobject]@{ Identity = $Id; IsDefault = $false; IsOrphan = $true; Rules = $RuleNames; Result = 'Investigate'; Policy = $null; FailReasons = @() })
                continue
            }
            $AllowedSenders = @($Policy.AllowedSenders).Where({ $_ }).Count
            $AllowedDomains = @($Policy.AllowedSenderDomains).Where({ $_ }).Count
            $FailReasons = @(
                if ($Policy.HighConfidencePhishAction -ne 'Quarantine') { 'HC-phish delivered' }
                if ($Policy.PhishSpamAction -ne 'Quarantine') { 'phish delivered' }
                if ($Policy.HighConfidenceSpamAction -ne 'Quarantine') { 'HC-spam delivered' }
                if ($Policy.SpamAction -notin @('MoveToJmf', 'Quarantine')) { "spam action $($Policy.SpamAction)" }
                if ($Policy.BulkSpamAction -notin @('MoveToJmf', 'Quarantine')) { "bulk action $($Policy.BulkSpamAction)" }
                if ($null -eq $Policy.BulkThreshold) { 'bulk threshold null (unexpected — verify policy data)' } elseif ($Policy.BulkThreshold -gt 6) { "bulk threshold $($Policy.BulkThreshold)" }
                if ($Policy.MarkAsSpamBulkMail -ne 'On') { 'MarkAsSpamBulkMail off' }
                if ($AllowedSenders -gt 0) { 'allowed senders non-empty' }
                if ($AllowedDomains -gt 0) { 'allowed domains non-empty' }
                if ($Policy.HighConfidencePhishQuarantineTag -ne 'AdminOnlyAccessPolicy') { 'HC-phish tag allows self-release' }
                if ($Policy.PhishZapEnabled -ne $true) { 'PhishZAP disabled' }
                if ($Policy.SpamZapEnabled -ne $true) { 'SpamZAP disabled' }
                if ($Policy.InlineSafetyTipsEnabled -ne $true) { 'SafetyTips disabled' }
            )
            if ($FailReasons.Count -gt 0) { $Passed = $false }
            $Rows.Add([pscustomobject]@{
                    Identity       = $Id
                    IsDefault      = $Policy.IsDefault -eq $true
                    IsOrphan       = $false
                    Rules          = if ($Policy.IsDefault -eq $true) { '' } else { $RuleNames }
                    Result         = if ($FailReasons.Count -gt 0) { 'Fail' } else { 'Pass' }
                    Policy         = $Policy
                    FailReasons    = $FailReasons
                    AllowedSenders = $AllowedSenders
                    AllowedDomains = $AllowedDomains
                })
        }

        if (-not $Passed) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new('❌ One or more anti-spam policies allow high-confidence phishing to be delivered (action is not Quarantine), set a permissive bulk threshold, or contain entries in the per-policy allowed-sender list that bypass spam, spoofing, and most phishing filtering for those senders. Operational exceptions for legitimate vendors belong in the **[Tenant Allow/Block List](https://security.microsoft.com/tenantAllowBlockList)**, where they can be reviewed and expired.')
        } elseif ($HasInvestigate) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new('⚠️ An enabled rule references a policy that does not exist in **Get-HostedContentFilterPolicy**; manual review is required.')
        } else {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ Anti-spam policies route high-confidence phishing to admin-only quarantine, use a strict bulk threshold, and contain no per-policy allow-sender entries that bypass filtering.')
        }

        $Order = @{ 'Fail' = 0; 'Investigate' = 1; 'Pass' = 2 }
        $Sorted = @($Rows | Sort-Object { $Order[$_.Result] }, Identity)
        $null = $Result.Append("`n`n")
        if ($Sorted.Count -gt 10) {
            $null = $Result.Append("Showing 10 of $($Sorted.Count) policies. [View all in Microsoft 365 Defender > Policies & rules > Threat policies > Anti-spam](https://security.microsoft.com/antispam)`n`n")
        }
        $null = $Result.Append("## [Anti-spam policy settings](https://security.microsoft.com/antispam)`n`n")
        $null = $Result.Append("| Policy | Scope | Filter actions | Bulk & ZAP | Allow lists & quarantine tag | Result |`n")
        $null = $Result.Append("| :----- | :---- | :------------- | :--------- | :--------------------------- | :----- |`n")
        foreach ($Row in $Sorted.Where({ $true }, 'First', 10)) {
            $PolicyCell = "$(ConvertTo-CippMarkdownCell $Row.Identity)$(if ($Row.IsDefault) { ' [default]' })"
            $Scope = if ($Row.IsOrphan -or $Row.Rules) { "Applied via $(if (($Row.Rules -split ', ').Count -gt 1) { 'rules' } else { 'rule' }) $(ConvertTo-CippMarkdownCell $Row.Rules)" } else { 'Default (catch-all)' }
            if ($Row.IsOrphan) {
                $Actions = '—'; $BulkZap = '—'; $AllowLists = '—'
            } else {
                $P = $Row.Policy
                $Actions = "Phish: $($P.PhishSpamAction)/HC:$($P.HighConfidencePhishAction) • Spam: $($P.SpamAction)/HC:$($P.HighConfidenceSpamAction) • Bulk: $($P.BulkSpamAction)"
                $Zap = if ($P.PhishZapEnabled -eq $true -and $P.SpamZapEnabled -eq $true) { 'Y' } else { 'N' }
                $BulkZap = "Bulk: $($P.BulkThreshold)/6 • MarkBulk: $(if ($P.MarkAsSpamBulkMail -eq 'On') { 'Y' } else { 'N' }) • ZAP: $Zap • SafetyTips: $(if ($P.InlineSafetyTipsEnabled -eq $true) { 'Y' } else { 'N' })"
                $AllowLists = "Senders: $($Row.AllowedSenders) • Domains: $($Row.AllowedDomains) • HC-Phish tag: $(ConvertTo-CippMarkdownCell $P.HighConfidencePhishQuarantineTag)"
            }
            $RowStatus = switch ($Row.Result) { 'Pass' { '✅ Pass' } 'Investigate' { '⚠️ Investigate (orphan rule reference)' } default { "❌ Fail ($($Row.FailReasons -join '; '))" } }
            $null = $Result.Append("| $PolicyCell | $Scope | $Actions | $BulkZap | $AllowLists | $RowStatus |`n")
        }
        if ($Sorted.Count -gt 10) { $null = $Result.Append("| ... | ... | ... | ... | ... | ... |`n") }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
