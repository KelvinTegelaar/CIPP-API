function Invoke-CippTestORCA106 {
    <#
    .SYNOPSIS
    Quarantine retention period is 30 days
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA106' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Quarantine retention period is 30 days' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.QuarantineRetentionPeriod -gt 15) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All anti-spam policies have quarantine retention period set to 30 days.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) anti-spam policies do not have quarantine retention period set to 30 days.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Quarantine Retention Period |`n")
            $null = $Result.Append("|------------|----------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.QuarantineRetentionPeriod) days |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA106' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Quarantine retention period is 30 days' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA106' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Quarantine retention period is 30 days' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
