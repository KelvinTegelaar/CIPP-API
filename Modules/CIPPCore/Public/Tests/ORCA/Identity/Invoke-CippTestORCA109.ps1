function Invoke-CippTestORCA109 {
    <#
    .SYNOPSIS
    Senders are not being allow listed in an unsafe manner
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA109' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Senders are not being allow listed in an unsafe manner' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $HasAllowedSenders = ($Policy.AllowedSenders -and $Policy.AllowedSenders.Count -gt 0) -or
            ($Policy.AllowedSenderDomains -and $Policy.AllowedSenderDomains.Count -gt 0)

            if (-not $HasAllowedSenders) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No anti-spam policies have sender allow lists configured.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have sender allow lists configured.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Allowed Senders | Allowed Sender Domains |`n"
            $Result += "|------------|----------------|----------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $SenderCount = if ($Policy.AllowedSenders) { $Policy.AllowedSenders.Count } else { 0 }
                $DomainCount = if ($Policy.AllowedSenderDomains) { $Policy.AllowedSenderDomains.Count } else { 0 }
                $Result += "| $($Policy.Identity) | $SenderCount | $DomainCount |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA109' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Senders are not being allow listed in an unsafe manner' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA109' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Senders are not being allow listed in an unsafe manner' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
