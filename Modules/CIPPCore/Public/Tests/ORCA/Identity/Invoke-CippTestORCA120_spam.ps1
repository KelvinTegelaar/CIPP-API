function Invoke-CippTestORCA120_spam {
    <#
    .SYNOPSIS
    Zero Hour Autopurge Enabled for Spam
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA120_spam' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Zero Hour Autopurge Enabled for Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.SpamZapEnabled -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-spam policies have Zero Hour Autopurge for Spam enabled.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies do not have Zero Hour Autopurge for Spam enabled.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Spam ZAP Enabled |`n"
            $Result += "|------------|-----------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.SpamZapEnabled) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA120_spam' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Zero Hour Autopurge Enabled for Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA120_spam' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Zero Hour Autopurge Enabled for Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
