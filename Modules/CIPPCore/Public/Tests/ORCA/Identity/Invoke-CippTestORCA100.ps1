function Invoke-CippTestORCA100 {
    <#
    .SYNOPSIS
    Bulk Complaint Level threshold is between 4 and 6
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA100' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Bulk Complaint Level threshold is between 4 and 6' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            # Check if BulkThreshold is between 4 and 6 (inclusive)
            if ($Policy.BulkThreshold -ge 4 -and $Policy.BulkThreshold -le 6) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-spam policies have appropriate Bulk Complaint Level (BCL) thresholds set between 4 and 6.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have BCL thresholds outside the recommended range (4-6).`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Current BCL Threshold |`n"
            $Result += "|------------|----------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.BulkThreshold) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA100' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Bulk Complaint Level threshold is between 4 and 6' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA100' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Bulk Complaint Level threshold is between 4 and 6' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
