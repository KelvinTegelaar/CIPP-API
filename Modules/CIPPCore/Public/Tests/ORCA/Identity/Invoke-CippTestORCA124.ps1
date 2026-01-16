function Invoke-CippTestORCA124 {
    <#
    .SYNOPSIS
    Safe attachments unknown malware response set to block messages
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.Action -in @('Block', 'Quarantine')) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All Safe Attachments policies have unknown malware response set to Block.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) Safe Attachments policies do not have unknown malware response set to Block.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Action |`n"
            $Result += "|------------|--------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.Action) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
