function Invoke-CippTestORCA104 {
    <#
    .SYNOPSIS
    High Confidence Phish action set to Quarantine message
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.HighConfidencePhishAction -eq 'Quarantine') {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All anti-spam policies have High Confidence Phish action set to Quarantine.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)`n`n")
            if ($PassedPolicies.Count -gt 0) {
                $null = $Result.Append("| Policy Name | Action |`n")
                $null = $Result.Append("|------------|--------|`n")
                foreach ($Policy in $PassedPolicies) {
                    $null = $Result.Append("| $($Policy.Identity) | $($Policy.HighConfidencePhishAction) |`n")
                }
            }
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("Some anti-spam policies do not have High Confidence Phish action set to Quarantine.`n`n")
            $null = $Result.Append("**Failed Policies:** $($FailedPolicies.Count) | **Passed Policies:** $($PassedPolicies.Count)`n`n")
            $null = $Result.Append("### Non-Compliant Policies`n`n")
            $null = $Result.Append("| Policy Name | Current Action | Recommended Action |`n")
            $null = $Result.Append("|------------|----------------|-------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.HighConfidencePhishAction) | Quarantine |`n")
            }
            $null = $Result.Append("`n**Remediation:** Update the HighConfidencePhishAction to 'Quarantine' for enhanced security.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
