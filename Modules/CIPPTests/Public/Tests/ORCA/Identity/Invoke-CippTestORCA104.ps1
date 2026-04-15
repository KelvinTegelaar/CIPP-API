function Invoke-CippTestORCA104 {
    <#
    .SYNOPSIS
    High Confidence Phish action set to Quarantine message
    #>
    param($Tenant)

    try {
        $AntiPhishPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $AntiPhishPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = @()
        $PassedPolicies = @()

        foreach ($Policy in $AntiPhishPolicies) {
            # Check if HighConfidencePhishAction is set to Quarantine
            if ($Policy.HighConfidencePhishAction -eq 'Quarantine') {
                $PassedPolicies += $Policy
            } else {
                $FailedPolicies += $Policy
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-phishing policies have High Confidence Phish action set to Quarantine.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)`n`n"
            if ($PassedPolicies.Count -gt 0) {
                $Result += "| Policy Name | Action |`n"
                $Result += "|------------|--------|`n"
                foreach ($Policy in $PassedPolicies) {
                    $Result += "| $($Policy.Identity) | $($Policy.HighConfidencePhishAction) |`n"
                }
            }
        } else {
            $Status = 'Failed'
            $Result = "Some anti-phishing policies do not have High Confidence Phish action set to Quarantine.`n`n"
            $Result += "**Failed Policies:** $($FailedPolicies.Count) | **Passed Policies:** $($PassedPolicies.Count)`n`n"
            $Result += "### Non-Compliant Policies`n`n"
            $Result += "| Policy Name | Current Action | Recommended Action |`n"
            $Result += "|------------|----------------|-------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.HighConfidencePhishAction) | Quarantine |`n"
            }
            $Result += "`n**Remediation:** Update the HighConfidencePhishAction to 'Quarantine' for enhanced security."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA104' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'High Confidence Phish action set to Quarantine message' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
