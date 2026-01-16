function Invoke-CippTestORCA110 {
    <#
    .SYNOPSIS
    Internal Sender notifications are disabled
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA110' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Internal Sender notifications are disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.InlineSafetyTipsEnabled -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-spam policies have internal sender notifications disabled.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have internal sender notifications enabled.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Inline Safety Tips Enabled |`n"
            $Result += "|------------|---------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.InlineSafetyTipsEnabled) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA110' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Internal Sender notifications are disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA110' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Internal Sender notifications are disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
