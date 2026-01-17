function Invoke-CippTestORCA156 {
    <#
    .SYNOPSIS
    Safe Links Policies are tracking when user clicks on safe links
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA156' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Safe Links Policies are tracking user clicks' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.TrackClicks -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All Safe Links policies are tracking user clicks.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) Safe Links policies are not tracking user clicks.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Track Clicks |`n"
            $Result += "|------------|-------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.TrackClicks) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA156' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Safe Links Policies are tracking user clicks' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA156' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Safe Links Policies are tracking user clicks' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
