function Invoke-CippTestORCA229 {
    <#
    .SYNOPSIS
    No trusted domains in Anti-phishing policy
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA229' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'No trusted domains in Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $HasTrustedDomains = ($Policy.ExcludedDomains -and $Policy.ExcludedDomains.Count -gt 0)

            if (-not $HasTrustedDomains) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No anti-phishing policies have trusted domains configured.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-phishing policies have trusted domains configured.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Excluded Domains Count |`n"
            $Result += "|------------|----------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Count = if ($Policy.ExcludedDomains) { $Policy.ExcludedDomains.Count } else { 0 }
                $Result += "| $($Policy.Identity) | $Count |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA229' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'No trusted domains in Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA229' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'No trusted domains in Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
