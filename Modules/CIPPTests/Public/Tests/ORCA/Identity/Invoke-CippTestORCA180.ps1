function Invoke-CippTestORCA180 {
    <#
    .SYNOPSIS
    Anti-phishing policy exists and EnableSpoofIntelligence is true
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA180' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Spoof Intelligence is enabled' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.EnableSpoofIntelligence -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All anti-phishing policies have Spoof Intelligence enabled.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) anti-phishing policies do not have Spoof Intelligence enabled.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Enable Spoof Intelligence |`n")
            $null = $Result.Append("|------------|--------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.EnableSpoofIntelligence) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA180' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Spoof Intelligence is enabled' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA180' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Spoof Intelligence is enabled' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
