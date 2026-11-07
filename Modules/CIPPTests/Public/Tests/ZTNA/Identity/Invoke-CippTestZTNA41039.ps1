function Invoke-CippTestZTNA41039 {
    <#
    .SYNOPSIS
    Zero-hour auto purge (ZAP) is enabled for malware, phishing, and spam in email
    #>
    param($Tenant)

    $TestId = 'ZTNA41039'
    $Name = 'Zero-hour auto purge (ZAP) is enabled for malware, phishing, and spam in email'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Exchange -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $MalwarePolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies').Where({ $null -ne $_ })
        $MalwareRules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterRules').Where({ $null -ne $_ })
        $SpamPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy').Where({ $null -ne $_ })
        $SpamRules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterRule').Where({ $null -ne $_ })
        if ($MalwarePolicies.Count -eq 0 -or $SpamPolicies.Count -eq 0 -or
            ($MalwareRules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoMalwareFilterRules' -CountsOnly)) -or
            ($SpamRules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoHostedContentFilterRule' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Anti-malware or anti-spam policies and rules have not been collected for this tenant. Refresh the ExoMalwareFilterPolicies, ExoHostedContentFilterPolicy and ExoHostedContentFilterRule caches.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $HasFailure = $false
        $HasInvestigate = $false
        $Surfaces = @(
            @{ Title = 'Anti-malware policy settings'; Policies = $MalwarePolicies; Rules = $MalwareRules; RuleKey = 'MalwareFilterPolicy'; Props = @('ZapEnabled'); Headers = @('ZAP for malware') }
            @{ Title = 'Anti-spam policy settings'; Policies = $SpamPolicies; Rules = $SpamRules; RuleKey = 'HostedContentFilterPolicy'; Props = @('PhishZapEnabled', 'SpamZapEnabled'); Headers = @('ZAP for phishing', 'ZAP for spam') }
        )
        $Sections = foreach ($Surface in $Surfaces) {
            $PolicyByIdentity = @{}
            foreach ($Policy in $Surface.Policies) { $PolicyByIdentity[[string]$Policy.Identity] = $Policy }
            $Rows = [System.Collections.Generic.List[object]]::new()
            $Defaults = $Surface.Policies.Where({ $_.IsDefault -eq $true })
            if ($Defaults.Count -eq 0) {
                $HasInvestigate = $true
                $Rows.Add([pscustomobject]@{ Identity = '—'; IsDefault = $false; Rule = $null; Values = @($null) * $Surface.Props.Count; Result = 'Investigate'; Detail = 'default policy not found' })
            }
            $Targets = @(
                foreach ($Policy in $Defaults) { [pscustomobject]@{ Policy = $Policy; Rule = $null; Identity = $Policy.Identity } }
                foreach ($Rule in $Surface.Rules.Where({ $_.State -eq 'Enabled' })) { [pscustomobject]@{ Policy = $PolicyByIdentity[[string]$Rule.($Surface.RuleKey)]; Rule = $Rule.Name; Identity = $Rule.($Surface.RuleKey) } }
            )
            foreach ($Target in $Targets) {
                if ($null -eq $Target.Policy) {
                    $HasInvestigate = $true
                    $Rows.Add([pscustomobject]@{ Identity = $Target.Identity; IsDefault = $false; Rule = $Target.Rule; Values = @($null) * $Surface.Props.Count; Result = 'Investigate'; Detail = 'referenced policy not found' })
                    continue
                }
                $Values = foreach ($Prop in $Surface.Props) { if ($Target.Policy.$Prop -is [bool]) { $Target.Policy.$Prop } else { $null } }
                $Values = @($Values)
                $RowResult = if ($Values.Where({ $_ -eq $false }).Count -gt 0) {
                    $HasFailure = $true; 'Fail'
                } elseif ($Values.Where({ $null -eq $_ }).Count -gt 0) {
                    $HasInvestigate = $true; 'Investigate'
                } else { 'Pass' }
                $Detail = if ($RowResult -eq 'Investigate') { if ($Surface.Props.Count -gt 1) { 'one or more ZAP values are unavailable' } else { 'ZapEnabled value is unavailable' } }
                $Rows.Add([pscustomobject]@{ Identity = $Target.Identity; IsDefault = $null -eq $Target.Rule; Rule = $Target.Rule; Values = $Values; Result = $RowResult; Detail = $Detail })
            }

            $Order = @{ 'Fail' = 0; 'Investigate' = 1; 'Pass' = 2 }
            $Sorted = @($Rows | Sort-Object { $Order[$_.Result] }, Identity)
            $Section = [System.Text.StringBuilder]::new("## $($Surface.Title)`n`n")
            $null = $Section.Append("| Policy identity | Applied via Rule | $($Surface.Headers -join ' | ') | Status |`n")
            $null = $Section.Append("| :-------------- | :--------------- | $(@($Surface.Headers.ForEach({ ':---' })) -join ' | ') | :----- |`n")
            foreach ($Row in $Sorted.Where({ $true }, 'First', 10)) {
                $Applied = if ($Row.IsDefault) { '— (catch-all)' } elseif ($Row.Rule) { ConvertTo-CippMarkdownCell $Row.Rule } else { '—' }
                $Cells = foreach ($Value in $Row.Values) { if ($null -eq $Value) { '⚠️ Unknown' } elseif ($Value) { '✅ Yes' } else { '❌ No' } }
                $RowStatus = switch ($Row.Result) { 'Pass' { '✅ Pass' } 'Fail' { '❌ Fail' } default { if ($Row.Detail) { "⚠️ Investigate — $($Row.Detail)" } else { '⚠️ Investigate' } } }
                $null = $Section.Append("| $(ConvertTo-CippMarkdownCell $Row.Identity)$(if ($Row.IsDefault) { ' [default]' }) | $Applied | $(@($Cells) -join ' | ') | $RowStatus |`n")
            }
            if ($Sorted.Count -gt 10) { $null = $Section.Append("| ... | ... | $(@($Surface.Headers.ForEach({ '...' })) -join ' | ') | ... |`n[Microsoft 365 Defender > Policies & rules > Threat policies](https://security.microsoft.com/threatpolicy)`n") }
            $Section.ToString()
        }

        if ($HasFailure) {
            $Status = 'Failed'
            $Summary = '❌ One or more in-scope policies disable ZAP for malware, spam, or phish; reclassified messages will remain in user mailboxes.'
        } elseif ($HasInvestigate) {
            $Status = 'Investigate'
            $Summary = '⚠️ An email ZAP policy surface could not be evaluated completely because policy or rule data is unavailable, or an enabled rule references a policy that does not exist; manual review is required.'
        } else {
            $Status = 'Passed'
            $Summary = '✅ Zero-hour auto purge is enabled for malware, spam, and phish across all in-scope EOP anti-malware and anti-spam policies.'
        }
        $Result = "$Summary`n`n$($Sections -join "`n")"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
