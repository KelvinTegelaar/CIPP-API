function Invoke-CippTestZTNA41033 {
    <#
    .SYNOPSIS
    Anti-phishing policies in Microsoft Defender for Office 365 are configured with impersonation and spoof protection
    #>
    param($Tenant)

    $TestId = 'ZTNA41033'
    $Name = 'Anti-phishing policies in Microsoft Defender for Office 365 are configured with impersonation and spoof protection'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies').Where({ $null -ne $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishRules').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -or ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoAntiPhishRules' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Anti-phishing policies or rules have not been collected for this tenant. Refresh the ExoAntiPhishPolicies cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }
        if (-not $Policies.Where({ $_.IsDefault -eq $true }, 'First')) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown '⚠️ `Get-AntiPhishPolicy` did not return the default policy. Refresh the Exchange Online cache and re-run.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        # Tag name -> recipient can self-release without notification; $null falls back to the built-in tag names
        $QuarantinePolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoQuarantinePolicy').Where({ $null -ne $_ })
        $SelfReleaseByTag = $null
        if ($QuarantinePolicies.Count -gt 0) {
            $SelfReleaseByTag = @{}
            foreach ($Q in $QuarantinePolicies) {
                $SelfReleaseByTag[[string]$Q.Name] = ([string]$Q.EndUserQuarantinePermissions -match 'PermissionToRelease:\s*True') -and $Q.ESNEnabled -ne $true
            }
        }
        $BuiltInQuarantineTags = @('AdminOnlyAccessPolicy', 'DefaultFullAccessPolicy', 'DefaultFullAccessWithNotificationPolicy')

        $PolicyNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Policies.Identity), [System.StringComparer]::OrdinalIgnoreCase)
        $EnabledRules = $Rules.Where({ $_.State -eq 'Enabled' })
        $OrphanRules = $EnabledRules.Where({ -not $PolicyNames.Contains([string]$_.AntiPhishPolicy) })
        $RulesForPolicy = @{}
        foreach ($Rule in $EnabledRules) {
            $Key = [string]$Rule.AntiPhishPolicy
            if (-not $RulesForPolicy.ContainsKey($Key)) { $RulesForPolicy[$Key] = [System.Collections.Generic.List[string]]::new() }
            $RulesForPolicy[$Key].Add([string]$Rule.Name)
        }

        $PolicyResults = foreach ($Policy in $Policies) {
            $IsBuiltIn = $Policy.IsBuiltInProtection -eq $true
            $IsDefault = $Policy.IsDefault -eq $true
            $Fails = [System.Collections.Generic.List[string]]::new()
            $Investigates = [System.Collections.Generic.List[string]]::new()
            $UserCount = @($Policy.TargetedUsersToProtect).Where({ $_ }).Count
            $DomainCount = @($Policy.TargetedDomainsToProtect).Where({ $_ }).Count

            if (-not $IsBuiltIn) {
                if (-not $IsDefault) {
                    if ($Policy.Enabled -ne $true) { $Fails.Add('policy disabled') }
                    if ($Policy.EnableTargetedUserProtection -ne $true -or $UserCount -eq 0) { $Fails.Add('targeted users empty') }
                    if ($Policy.EnableTargetedDomainsProtection -ne $true -or $DomainCount -eq 0) { $Fails.Add('targeted domains empty') }
                    if ($Policy.EnableOrganizationDomainsProtection -ne $true) { $Fails.Add('org domains not protected') }
                    if ($Policy.EnableTargetedUserProtection -eq $true -and $Policy.EnableSimilarUsersSafetyTips -ne $true) { $Fails.Add('similar users safety tips off') }
                    if ($Policy.EnableTargetedDomainsProtection -eq $true -and $Policy.EnableSimilarDomainsSafetyTips -ne $true) { $Fails.Add('similar domains safety tips off') }
                    if ($Policy.EnableUnusualCharactersSafetyTips -ne $true) { $Fails.Add('unusual characters safety tips off') }
                }
                if ($Policy.EnableMailboxIntelligence -ne $true -or $Policy.EnableMailboxIntelligenceProtection -ne $true) { $Fails.Add('mailbox intelligence off') }
                if ($Policy.EnableSpoofIntelligence -ne $true) { $Fails.Add('spoof off') }
                if ($Policy.HonorDmarcPolicy -ne $true) { $Fails.Add('dmarc not honored') }
                if (-not $IsDefault) {
                    if ($Policy.AuthenticationFailAction -ne 'Quarantine') { $Fails.Add('auth-fail delivered') }
                    if ($Policy.EnableUnauthenticatedSender -ne $true) { $Fails.Add('unauthenticated sender indicator off') }
                    if ($Policy.EnableViaTag -ne $true) { $Fails.Add('via tag off') }
                    if ($Policy.EnableFirstContactSafetyTips -ne $true) { $Fails.Add('first contact safety tips off') }
                    if ($Policy.HonorDmarcPolicy -eq $true -and $Policy.DmarcQuarantineAction -ne 'Quarantine') { $Fails.Add('DMARC quarantine action not quarantine') }
                    if ($Policy.HonorDmarcPolicy -eq $true -and $Policy.DmarcRejectAction -ne 'Reject') { $Fails.Add('DMARC reject action not reject') }
                }
                foreach ($Check in @(
                        @('EnableTargetedUserProtection', 'TargetedUserProtectionAction'),
                        @('EnableTargetedDomainsProtection', 'TargetedDomainProtectionAction'),
                        @('EnableMailboxIntelligenceProtection', 'MailboxIntelligenceProtectionAction'))) {
                    if ($Policy.($Check[0]) -eq $true -and $Policy.($Check[1]) -ne 'Quarantine') { $Fails.Add("impersonation action not enforced: $($Check[1])") }
                }
                $UnverifiedTags = [System.Collections.Generic.List[string]]::new()
                foreach ($TagProperty in @('TargetedUserQuarantineTag', 'TargetedDomainQuarantineTag', 'MailboxIntelligenceQuarantineTag', 'SpoofQuarantineTag')) {
                    $Tag = [string]$Policy.$TagProperty
                    if ([string]::IsNullOrEmpty($Tag)) { continue }
                    $SelfRelease = if ($null -ne $SelfReleaseByTag -and $SelfReleaseByTag.ContainsKey($Tag)) { $SelfReleaseByTag[$Tag] } else { $Tag -eq 'DefaultFullAccessPolicy' }
                    if ($SelfRelease) {
                        $Fails.Add("self-release quarantine tag: $TagProperty")
                    } elseif ($null -eq $SelfReleaseByTag -and $Tag -notin $BuiltInQuarantineTags) {
                        $UnverifiedTags.Add($TagProperty)
                    }
                }
                if ($Fails.Count -eq 0) {
                    foreach ($TagProperty in $UnverifiedTags) { $Investigates.Add("quarantine policy unavailable for custom tag: $TagProperty") }
                    if ($Policy.PhishThresholdLevel -lt 3) { $Investigates.Add("phish threshold=$($Policy.PhishThresholdLevel), below recommended minimum of 3") }
                }
            }

            $RowStatus = if ($Fails.Count -gt 0) { 'Fail' } elseif ($Investigates.Count -gt 0) { 'Investigate' } else { 'Pass' }
            $Suffixes = @(
                if ($IsDefault) { '[default]' }
                if ($IsBuiltIn) { '[built-in]' }
                if ($Policy.Enabled -eq $false) { '[disabled]' }
            )
            $Spoof = if ($Policy.EnableSpoofIntelligence -eq $true) { 'Y' } else { 'N' }
            $Dmarc = if ($Policy.HonorDmarcPolicy -eq $true) { 'Y' } else { 'N' }
            $Org = if ($Policy.EnableOrganizationDomainsProtection -eq $true) { 'Y' } else { 'N' }
            $Mbx = if ($Policy.EnableMailboxIntelligence -eq $true -and $Policy.EnableMailboxIntelligenceProtection -eq $true) { 'Y' } else { 'N' }
            [pscustomobject]@{
                Identity       = (@([string]$Policy.Identity) + $Suffixes) -join ' '
                IsDefault      = $IsDefault
                IsBuiltIn      = $IsBuiltIn
                Applied        = $RulesForPolicy.ContainsKey([string]$Policy.Identity)
                Scope          = if ($RulesForPolicy.ContainsKey([string]$Policy.Identity)) { 'Applied via rule ' + ($RulesForPolicy[[string]$Policy.Identity] -join ', ') } else { 'Not applied' }
                Impersonation  = if ($IsBuiltIn) { '—' } else { "Users: $UserCount • Domains: $DomainCount • Org: $Org • MailboxIntel: $Mbx" }
                Authentication = "Spoof: $Spoof • DMARC: $Dmarc • AuthFail: $($Policy.AuthenticationFailAction)"
                PhishThreshold = switch ([int]$Policy.PhishThresholdLevel) { 1 { '1 Standard' } 2 { '2 Aggressive' } 3 { '3 More aggressive' } 4 { '4 Most aggressive' } default { "$($Policy.PhishThresholdLevel)" } }
                Result         = switch ($RowStatus) { 'Fail' { "Fail ($($Fails -join '; '))" } 'Investigate' { "Investigate ($($Investigates -join '; '))" } default { 'Pass' } }
                RowStatus      = $RowStatus
            }
        }
        $PolicyResults = @($PolicyResults)

        $DefaultResult = $PolicyResults.Where({ $_.IsDefault }, 'First')[0]
        $RuleRefPolicies = $PolicyResults.Where({ -not $_.IsBuiltIn -and -not $_.IsDefault -and $_.Applied })
        $Applicable = $PolicyResults.Where({ -not $_.IsBuiltIn -and ($_.IsDefault -or $_.Applied) })
        $AnyCustomPass = $RuleRefPolicies.Where({ $_.RowStatus -eq 'Pass' }).Count -gt 0
        $AnyCustomFail = $RuleRefPolicies.Where({ $_.RowStatus -eq 'Fail' }).Count -gt 0
        $AnyApplicableInvestigate = $Applicable.Where({ $_.RowStatus -eq 'Investigate' }).Count -gt 0
        $FailCount = $Applicable.Where({ $_.RowStatus -eq 'Fail' }).Count
        $IsFail = ($DefaultResult -and $DefaultResult.RowStatus -eq 'Fail') -or $AnyCustomFail

        if ($IsFail) {
            $Status = 'Failed'
            $Aggregation = "$FailCount $(if ($FailCount -eq 1) { 'policy' } else { 'policies' }) non-compliant"
            if ($OrphanRules.Count -gt 0) { $Aggregation = "$Aggregation, $($OrphanRules.Count) orphaned $(if ($OrphanRules.Count -eq 1) { 'rule' } else { 'rules' })" }
            $Result = [System.Text.StringBuilder]::new('❌ One or more anti-phishing policies disable a key control (spoof, DMARC, mailbox intelligence, or impersonation protection), have empty impersonation lists, or apply non-quarantine actions to phishing.')
        } elseif (-not $AnyCustomPass -or $AnyApplicableInvestigate -or $OrphanRules.Count -gt 0) {
            $Status = 'Investigate'
            if ($OrphanRules.Count -gt 0) {
                $Aggregation = @(foreach ($Rule in $OrphanRules) { "orphaned rule $($Rule.Name) references phantom policy" }) -join '; '
                $Result = [System.Text.StringBuilder]::new("⚠️ An enabled anti-phishing rule references a policy that does not exist. Manual review is required to confirm the customer's intent.")
            } elseif ($AnyApplicableInvestigate) {
                $Aggregation = if ($DefaultResult -and $DefaultResult.RowStatus -eq 'Investigate') { 'phish threshold below 3 in default policy' } else { 'phish threshold below 3 in one or more policies' }
                $Result = [System.Text.StringBuilder]::new("⚠️ One or more anti-phishing policies have ``PhishThresholdLevel`` below 3 (Microsoft recommends 3 — More aggressive — for Standard, and 4 — Most aggressive — for Strict); manual review is required to confirm the customer's intent.")
            } else {
                $Aggregation = 'no custom anti-phishing policy with full impersonation controls is applied to any recipient'
                $Result = [System.Text.StringBuilder]::new('⚠️ Only the default anti-phishing policy is in effect. The default policy is evaluated against the minimum spoof and DMARC subset only; it does not enforce targeted-user, domain, or org-domain impersonation protection. Configure a custom policy with impersonation controls and assign it via an enabled rule.')
            }
        } else {
            $Status = 'Passed'
            $Aggregation = 'at least one compliant policy applies, default policy meets required subset, no orphaned rules'
            $Result = [System.Text.StringBuilder]::new('✅ Anti-phishing policies are configured with spoof intelligence, DMARC honoring, mailbox intelligence, and impersonation protection for users and domains; impersonation and spoof verdicts are quarantined without unapproved self-release.')
        }

        $Overall = switch ($Status) { 'Passed' { 'Pass' } 'Failed' { 'Fail' } default { 'Investigate' } }
        $null = $Result.Append("`n`n**Overall: $Overall** — $(ConvertTo-CippMarkdownCell $Aggregation)`n`n")
        $null = $Result.Append("### [Microsoft 365 Defender > Policies & rules > Anti-phishing](https://security.microsoft.com/antiphishing)`n`n")
        if ($PolicyResults.Count -gt 10) {
            $null = $Result.Append("Showing 10 of $($PolicyResults.Count) policies. [View all in Microsoft 365 Defender](https://security.microsoft.com/antiphishing)`n`n")
        }
        $null = $Result.Append("| Policy | Scope | Impersonation | Authentication | Phish threshold | Result |`n")
        $null = $Result.Append("| :----- | :---- | :------------ | :------------- | --------------: | :----- |`n")
        $Order = @{ 'Fail' = 0; 'Investigate' = 1; 'Pass' = 2 }
        foreach ($Row in @($PolicyResults | Sort-Object { $Order[$_.RowStatus] }, Identity).Where({ $true }, 'First', 10)) {
            $null = $Result.Append("| $(ConvertTo-CippMarkdownCell $Row.Identity) | $(ConvertTo-CippMarkdownCell $Row.Scope) | $($Row.Impersonation) | $(ConvertTo-CippMarkdownCell $Row.Authentication) | $($Row.PhishThreshold) | $(ConvertTo-CippMarkdownCell $Row.Result) |`n")
        }
        if ($PolicyResults.Count -gt 10) { $null = $Result.Append("| ... | ... | ... | ... | ... | ... |`n") }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
