function Invoke-CippTestORCA101 {
    <#
    .SYNOPSIS
    Bulk is marked as spam
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA101' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Bulk is marked as spam' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.MarkAsSpamBulkMail -eq 'On') {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-spam policies are configured to mark bulk mail as spam.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)`n`n"
            if ($PassedPolicies.Count -gt 0) {
                $Result += "| Policy Name | Mark As Spam Bulk Mail |`n"
                $Result += "|------------|------------------------|`n"
                foreach ($Policy in $PassedPolicies) {
                    $Result += "| $($Policy.Identity) | $($Policy.MarkAsSpamBulkMail) |`n"
                }
            }
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies are not configured to mark bulk mail as spam.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Mark As Spam Bulk Mail |`n"
            $Result += "|------------|------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.MarkAsSpamBulkMail) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA101' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Bulk is marked as spam' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA101' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Bulk is marked as spam' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
