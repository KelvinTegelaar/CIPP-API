function Invoke-CippTestORCA220 {
    <#
    .SYNOPSIS
    Advanced Phish filter Threshold level is adequate
    #>
    param($Tenant)
    
    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'
        
        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA220' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Advanced Phish filter Threshold level is adequate' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            # PhishThresholdLevel: 1=Standard, 2=Aggressive, 3=More Aggressive, 4=Most Aggressive
            if ($Policy.PhishThresholdLevel -ge 2) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All anti-phishing policies have adequate phishing threshold levels (2 or higher).`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) anti-phishing policies have inadequate phishing threshold levels.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Phish Threshold Level |`n")
            $null = $Result.Append("|------------|----------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.PhishThresholdLevel) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA220' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Advanced Phish filter Threshold level is adequate' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA220' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Advanced Phish filter Threshold level is adequate' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
