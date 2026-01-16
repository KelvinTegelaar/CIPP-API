function Invoke-CippTestORCA179 {
    <#
    .SYNOPSIS
    Safe Links is enabled intra-organization
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.EnableForInternalSenders -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All Safe Links policies are enabled for internal senders.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) Safe Links policies are not enabled for internal senders.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Enable For Internal Senders |`n"
            $Result += "|------------|----------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.EnableForInternalSenders) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
