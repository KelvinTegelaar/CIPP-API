function Invoke-CippTestZTNA41029 {
    <#
    .SYNOPSIS
    Anti-malware policies are configured according to recommended settings
    #>
    param($Tenant)

    $TestId = 'ZTNA41029'
    $Name = 'Anti-malware policies are configured according to recommended settings'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Exchange -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies').Where({ $null -ne $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterRules').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -or ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoMalwareFilterRules' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Anti-malware policies or rules have not been collected for this tenant. Refresh the ExoMalwareFilterPolicies cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $PolicyByIdentity = @{}
        foreach ($Policy in $Policies) { $PolicyByIdentity[[string]$Policy.Identity] = $Policy }

        $InScopeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $InScope = [System.Collections.Generic.List[object]]::new()
        foreach ($Policy in $Policies.Where({ $_.IsDefault -eq $true })) {
            if ($InScopeIds.Add([string]$Policy.Identity)) { $InScope.Add($Policy) }
        }
        $OrphanRules = [System.Collections.Generic.List[string]]::new()
        foreach ($Rule in $Rules.Where({ $_.State -eq 'Enabled' })) {
            $Policy = $PolicyByIdentity[[string]$Rule.MalwareFilterPolicy]
            if ($Policy) {
                if ($InScopeIds.Add([string]$Policy.Identity)) { $InScope.Add($Policy) }
            } else {
                $OrphanRules.Add([string]$Rule.Name)
            }
        }

        $RowResults = @{}
        $Investigate = [System.Collections.Generic.List[string]]::new()
        $NonCompliant = 0
        foreach ($Policy in $InScope) {
            $RowResults[[string]$Policy.Identity] = if ($OrphanRules.Count -gt 0) {
                '⚠️ Investigate'
            } elseif ($Policy.QuarantineTag -ne 'AdminOnlyAccessPolicy') {
                $Investigate.Add([string]$Policy.Identity)
                '⚠️ Investigate'
            } elseif ($Policy.EnableFileFilter -ne $true -or $Policy.ZapEnabled -ne $true) {
                $NonCompliant++
                '❌ Fail'
            } else {
                '✅ Pass'
            }
        }

        if ($OrphanRules.Count -gt 0) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new("⚠️ **Investigate:** $($OrphanRules.Count) enabled rule(s) reference a policy that does not exist (orphan rule); manual review is required. Orphaned rules: $(($OrphanRules | ConvertTo-CippMarkdownCell) -join ', ').")
        } elseif ($Investigate.Count -gt 0) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new("⚠️ **Investigate:** One or more in-scope policies apply a customer-defined quarantine policy whose release behavior cannot be confirmed by this check. Affected: $(($Investigate | ConvertTo-CippMarkdownCell) -join ', ').")
        } elseif ($NonCompliant -gt 0) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new('❌ One or more in-scope anti-malware policies have the Common Attachment Filter disabled, ZAP disabled, or apply a quarantine policy that permits recipient self-release of malware.')
        } else {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ All in-scope anti-malware policies have the Common Attachment Filter enabled, zero-hour auto purge enabled, and route detected malware to an admin-only quarantine.')
        }

        if ($InScope.Count -gt 0) {
            $null = $Result.Append("`n`n## [In-scope anti-malware policies](https://security.microsoft.com/antimalwarev2)`n`n")
            $null = $Result.Append("| Identity | Is default | Common attachment filter | File types (count) | ZAP | Quarantine tag | Applied | Result |`n")
            $null = $Result.Append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |`n")
            foreach ($Policy in $InScope.Where({ $true }, 'First', 10)) {
                $IsDefault = $Policy.IsDefault -eq $true
                $FileFilter = if ($Policy.EnableFileFilter -eq $true) { '✅ Yes' } else { '❌ No' }
                $Zap = if ($Policy.ZapEnabled -eq $true) { '✅ Yes' } else { '❌ No' }
                $null = $Result.Append("| $(ConvertTo-CippMarkdownCell $Policy.Identity) | $(if ($IsDefault) { 'Yes' } else { 'No' }) | $FileFilter | $(@($Policy.FileTypes).Where({ $_ }).Count) | $Zap | $(ConvertTo-CippMarkdownCell $Policy.QuarantineTag) | $(if ($IsDefault) { 'Default catch-all' } else { 'Via enabled rule' }) | $($RowResults[[string]$Policy.Identity]) |`n")
            }
            if ($InScope.Count -gt 10) {
                $null = $Result.Append("`n... and $($InScope.Count - 10) more. [View all anti-malware policies](https://security.microsoft.com/antimalwarev2)`n")
            }
            $InternalNotify = $InScope.Where({ $_.EnableInternalSenderAdminNotifications -eq $true }).Count
            $ExternalNotify = $InScope.Where({ $_.EnableExternalSenderAdminNotifications -eq $true }).Count
            $null = $Result.Append("`n_Of $($InScope.Count) in-scope policies, $InternalNotify have internal sender admin notifications enabled and $ExternalNotify have external sender admin notifications enabled. Microsoft's baseline recommends both off; these settings do not affect this check's Pass/Fail._`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
