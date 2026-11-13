function Invoke-CippTestZTNA41031 {
    <#
    .SYNOPSIS
    Safe Attachments policies in Microsoft Defender for Office 365 are configured to detonate and block
    #>
    param($Tenant)

    $TestId = 'ZTNA41031'
    $Name = 'Safe Attachments policies in Microsoft Defender for Office 365 are configured to detonate and block'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies').Where({ $null -ne $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentRules').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -or ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoSafeAttachmentRules' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Safe Attachments policies or rules have not been collected for this tenant. Refresh the ExoSafeAttachmentPolicies cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $PolicyByIdentity = @{}
        foreach ($Policy in $Policies) { $PolicyByIdentity[[string]$Policy.Identity] = $Policy }
        $RuleForPolicy = @{}
        foreach ($Rule in $Rules.Where({ $_.State -eq 'Enabled' })) { $RuleForPolicy[[string]$Rule.SafeAttachmentPolicy] = [string]$Rule.Name }

        $BuiltIn = $Policies.Where({ $_.IsBuiltInProtection -eq $true }, 'First')[0]
        $InScopeIds = [System.Collections.Generic.List[string]]::new()
        if ($BuiltIn) { $InScopeIds.Add([string]$BuiltIn.Identity) }
        foreach ($Id in $RuleForPolicy.Keys) { if (-not $InScopeIds.Contains($Id)) { $InScopeIds.Add($Id) } }

        $Passed = $null -ne $BuiltIn
        $HasInvestigate = $false
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $InScopeIds) {
            $Policy = $PolicyByIdentity[$Id]
            if ($null -eq $Policy) {
                $HasInvestigate = $true
                $Rows.Add([pscustomobject]@{ Identity = "$Id (not found)"; Type = '—'; Enable = $null; Action = '—'; QuarantineTag = '—'; Redirect = $null; RedirectAddress = '—'; Rule = $RuleForPolicy[$Id]; Result = 'Investigate' })
                continue
            }
            $RowResult = if ($Policy.Enable -eq $true -and $Policy.Action -eq 'Block' -and $Policy.QuarantineTag -eq 'AdminOnlyAccessPolicy') { 'Pass' } else { $Passed = $false; 'Fail' }
            $Rows.Add([pscustomobject]@{
                    Identity        = $Id
                    Type            = if ($Policy.IsBuiltInProtection -eq $true) { 'Built-in' } elseif ($Policy.IsDefault -eq $true) { 'Default' } else { 'Custom' }
                    Enable          = $Policy.Enable
                    Action          = $Policy.Action
                    QuarantineTag   = $Policy.QuarantineTag
                    Redirect        = $Policy.Redirect
                    RedirectAddress = if ($Policy.RedirectAddress) { $Policy.RedirectAddress } else { '—' }
                    Rule            = if ($Policy.IsBuiltInProtection -eq $true) { '' } else { $RuleForPolicy[$Id] }
                    Result          = $RowResult
                })
        }
        foreach ($Policy in $Policies) {
            if ($InScopeIds.Contains([string]$Policy.Identity)) { continue }
            $Rows.Add([pscustomobject]@{
                    Identity        = $Policy.Identity
                    Type            = if ($Policy.IsBuiltInProtection -eq $true) { 'Built-in' } elseif ($Policy.IsDefault -eq $true) { 'Default' } else { 'Custom' }
                    Enable          = $Policy.Enable
                    Action          = $Policy.Action
                    QuarantineTag   = $Policy.QuarantineTag
                    Redirect        = $Policy.Redirect
                    RedirectAddress = if ($Policy.RedirectAddress) { $Policy.RedirectAddress } else { '—' }
                    Rule            = ''
                    Result          = 'Not applied'
                })
        }

        if (-not $Passed) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new('❌ The Built-in Protection policy is missing or non-compliant, or one or more policies referenced by enabled rules is disabled, set to Allow/DynamicDelivery, or applies a quarantine policy that lets recipients self-release; detonated malware can still reach end users.')
        } elseif ($HasInvestigate) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new('⚠️ An enabled Safe Attachments rule references a policy that does not exist; manual review is required.')
        } else {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ Safe Attachments is enabled across the Built-in Protection preset and any policies referenced by enabled rules, set to Block detonated malware, and routes detections to admin-only quarantine.')
        }

        $Order = @{ 'Fail' = 0; 'Investigate' = 1; 'Pass' = 2; 'Not applied' = 3 }
        $Sorted = @($Rows | Sort-Object { $Order[$_.Result] }, Identity)
        $null = $Result.Append("`n`n")
        if ($Sorted.Count -gt 10) {
            $null = $Result.Append("Showing 10 of $($Sorted.Count) policies. [View all in Microsoft 365 Defender > Policies & rules > Threat policies > Safe Attachments](https://security.microsoft.com/safeattachmentv2)`n`n")
        }
        $null = $Result.Append("| Identity | Type | Enable | Action | Quarantine policy | Redirect | Redirect address | Applied via rule | Result |`n")
        $null = $Result.Append("| :------- | :--- | :----- | :----- | :---------------- | :------- | :--------------- | :--------------- | :----- |`n")
        foreach ($Row in $Sorted.Where({ $true }, 'First', 10)) {
            $Enable = if ($null -eq $Row.Enable) { '—' } elseif ($Row.Enable) { '✅ Yes' } else { '❌ No' }
            $Action = if ($Row.Action -eq '—') { '—' } elseif ($Row.Action -eq 'Block') { '✅ Block' } else { "❌ $($Row.Action)" }
            $Quarantine = if ($Row.QuarantineTag -eq '—') { '—' } elseif ($Row.QuarantineTag -eq 'AdminOnlyAccessPolicy') { '✅ AdminOnlyAccessPolicy' } else { "❌ $(ConvertTo-CippMarkdownCell $Row.QuarantineTag)" }
            $Redirect = if ($null -eq $Row.Redirect) { '—' } elseif ($Row.Redirect) { 'Yes' } else { 'No' }
            $RowStatus = switch ($Row.Result) { 'Pass' { '✅ Pass' } 'Fail' { '❌ Fail' } 'Investigate' { '⚠️ Investigate' } default { 'Not applied' } }
            $null = $Result.Append("| $(ConvertTo-CippMarkdownCell $Row.Identity) | $($Row.Type) | $Enable | $Action | $Quarantine | $Redirect | $(ConvertTo-CippMarkdownCell $Row.RedirectAddress) | $(ConvertTo-CippMarkdownCell $Row.Rule) | $RowStatus |`n")
        }
        if ($Sorted.Count -gt 10) { $null = $Result.Append("| ... | ... | ... | ... | ... | ... | ... | ... | ... |`n") }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
