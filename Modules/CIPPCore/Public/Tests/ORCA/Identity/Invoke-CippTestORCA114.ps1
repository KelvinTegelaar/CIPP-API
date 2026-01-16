function Invoke-CippTestORCA114 {
    <#
    .SYNOPSIS
    No IP Allow Lists have been configured
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA114' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'No IP Allow Lists have been configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

$FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $HasIPAllowList = ($Policy.IPAllowList -and $Policy.IPAllowList.Count -gt 0)

            if (-not $HasIPAllowList) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No anti-spam policies have IP allow lists configured.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have IP allow lists configured.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | IP Allow List Count |`n"
            $Result += "|------------|-------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $IPCount = if ($Policy.IPAllowList) { $Policy.IPAllowList.Count } else { 0 }
                $Result += "| $($Policy.Identity) | $IPCount |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA114' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'No IP Allow Lists have been configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA114' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'No IP Allow Lists have been configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
