function Invoke-CippTestZTNA41032 {
    <#
    .SYNOPSIS
    Safe Links policies in Microsoft Defender for Office 365 are configured to scan and block malicious URLs
    #>
    param($Tenant)

    $TestId = 'ZTNA41032'
    $Name = 'Safe Links policies in Microsoft Defender for Office 365 are configured to scan and block malicious URLs'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies').Where({ $null -ne $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksRules').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -or ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoSafeLinksRules' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Safe Links policies or rules have not been collected for this tenant. Refresh the ExoSafeLinksPolicies cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        # Standard/Strict baseline; Built-in Protection is weaker by design and only reported
        $Baseline = [ordered]@{
            EnableSafeLinksForEmail  = $true
            EnableSafeLinksForTeams  = $true
            EnableSafeLinksForOffice = $true
            ScanUrls                 = $true
            DeliverMessageAfterScan  = $true
            EnableForInternalSenders = $true
            DisableUrlRewrite        = $false
            AllowClickThrough        = $false
            TrackClicks              = $true
        }

        $PolicyByIdentity = @{}
        foreach ($Policy in $Policies) { $PolicyByIdentity[[string]$Policy.Identity] = $Policy }
        $RuleForPolicy = @{}
        $EnabledRules = $Rules.Where({ $_.State -eq 'Enabled' })
        foreach ($Rule in $EnabledRules) { $RuleForPolicy[[string]$Rule.SafeLinksPolicy] = [string]$Rule.Name }

        $BuiltIn = $Policies.Where({ $_.IsBuiltInProtection -eq $true }, 'First')[0]
        $InScopeIds = [System.Collections.Generic.List[string]]::new()
        if ($BuiltIn) { $InScopeIds.Add([string]$BuiltIn.Identity) }
        foreach ($Id in $RuleForPolicy.Keys) { if (-not $InScopeIds.Contains($Id)) { $InScopeIds.Add($Id) } }

        $Passed = $EnabledRules.Count -gt 0
        $HasInvestigate = $false
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $InScopeIds) {
            $Policy = $PolicyByIdentity[$Id]
            $IsRuleScoped = $RuleForPolicy.ContainsKey($Id)
            if ($null -eq $Policy) {
                $HasInvestigate = $true
                $Rows.Add([pscustomobject]@{ Identity = $Id; IsBuiltIn = $false; Rule = $RuleForPolicy[$Id]; NonCompliant = 'Referenced policy not found in Get-SafeLinksPolicy'; Result = 'Investigate' })
                continue
            }
            $NonCompliant = foreach ($Prop in $Baseline.Keys) {
                if ($Policy.$Prop -ne $Baseline[$Prop]) { "$Prop=$($Policy.$Prop)" }
            }
            $RowResult = if ($NonCompliant) { 'Fail' } else { 'Pass' }
            if ($IsRuleScoped -and $RowResult -eq 'Fail') { $Passed = $false }
            $IsBuiltIn = $Policy.IsBuiltInProtection -eq $true
            $Rows.Add([pscustomobject]@{ Identity = $Id; IsBuiltIn = $IsBuiltIn; Rule = if ($IsBuiltIn) { '' } else { $RuleForPolicy[$Id] }; NonCompliant = @($NonCompliant) -join ', '; Result = $RowResult })
        }

        if (-not $Passed) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new('❌ Either no custom or preset Safe Links rule is enabled (Built-in Protection alone does not meet the Standard/Strict baseline) or one or more enabled rule-referenced policies disables a scanning surface, allows click-through, skips internal senders, or disables URL rewriting; users can encounter weaponized URLs in collaboration surfaces.')
        } elseif ($HasInvestigate) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new('⚠️ An enabled Safe Links rule references a policy that does not exist in Get-SafeLinksPolicy; manual review is required.')
        } else {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ Every Safe Links policy in use scans URLs for email, Teams, and Office apps at time of click; rewrites URLs in email; covers internal senders; and prevents users from clicking through warnings.')
        }

        $Order = @{ 'Fail' = 0; 'Investigate' = 1; 'Pass' = 2 }
        $Sorted = @($Rows | Sort-Object { $Order[$_.Result] }, Identity)
        $null = $Result.Append("`n`n")
        if ($Sorted.Count -gt 10) {
            $null = $Result.Append("Showing 10 of $($Sorted.Count) policies. [View all in Microsoft 365 Defender > Policies & rules > Threat policies > Safe Links](https://security.microsoft.com/safelinksv2)`n`n")
        }
        $null = $Result.Append("| Result | Policy | Applied via rule | Non-compliant settings |`n")
        $null = $Result.Append("| :----- | :----- | :--------------- | :--------------------- |`n")
        foreach ($Row in $Sorted.Where({ $true }, 'First', 10)) {
            $RowStatus = switch ($Row.Result) { 'Pass' { '✅ Pass' } 'Fail' { '❌ Fail' } default { '⚠️ Investigate' } }
            $PolicyName = if ($Row.IsBuiltIn) { "(Built-in) $($Row.Identity)" } else { $Row.Identity }
            $null = $Result.Append("| $RowStatus | $(ConvertTo-CippMarkdownCell $PolicyName) | $(ConvertTo-CippMarkdownCell $Row.Rule) | $(ConvertTo-CippMarkdownCell $Row.NonCompliant) |`n")
        }
        if ($Sorted.Count -gt 10) { $null = $Result.Append("| ... | ... | ... | ... |`n") }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
