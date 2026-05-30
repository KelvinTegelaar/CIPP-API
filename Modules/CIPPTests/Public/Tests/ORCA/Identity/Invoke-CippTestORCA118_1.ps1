function Invoke-CippTestORCA118_1 {
    <#
    .SYNOPSIS
    Domains not allow listed in Anti-Spam
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $HasAllowedDomains = ($Policy.AllowedSenderDomains -and $Policy.AllowedSenderDomains.Count -gt 0)

            if (-not $HasAllowedDomains) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("No anti-spam policies have allowed sender domains configured.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) anti-spam policies have allowed sender domains configured.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Allowed Sender Domains Count |`n")
            $null = $Result.Append("|------------|------------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $Count = if ($Policy.AllowedSenderDomains) { $Policy.AllowedSenderDomains.Count } else { 0 }
                $null = $Result.Append("| $($Policy.Identity) | $Count |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
