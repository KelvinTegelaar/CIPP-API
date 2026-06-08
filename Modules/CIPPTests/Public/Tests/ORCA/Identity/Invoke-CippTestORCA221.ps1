function Invoke-CippTestORCA221 {
    <#
    .SYNOPSIS
    Mailbox intelligence is enabled in anti-phishing policies
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA221' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Mailbox intelligence is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.EnableMailboxIntelligence -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All anti-phishing policies have mailbox intelligence enabled.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) anti-phishing policies do not have mailbox intelligence enabled.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Enable Mailbox Intelligence |`n")
            $null = $Result.Append("|------------|----------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.EnableMailboxIntelligence) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA221' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Mailbox intelligence is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA221' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Mailbox intelligence is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
