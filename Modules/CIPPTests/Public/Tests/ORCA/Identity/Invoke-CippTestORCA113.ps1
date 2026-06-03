function Invoke-CippTestORCA113 {
    <#
    .SYNOPSIS
    AllowClickThrough is disabled in Safe Links policies
    #>
    param($Tenant)

    try {
        $SafeLinksPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SafeLinksPolicies) {
            if ($Policy.DoNotAllowClickThrough -eq $true) {
                $PassedPolicies.Add($Policy)
            } else {
                $FailedPolicies.Add($Policy)
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All Safe Links policies have click-through disabled (DoNotAllowClickThrough = true).`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)`n`n")
            if ($PassedPolicies.Count -gt 0) {
                $null = $Result.Append("| Policy Name | DoNotAllowClickThrough |`n")
                $null = $Result.Append("|------------|----------------------|`n")
                foreach ($Policy in $PassedPolicies) {
                    $null = $Result.Append("| $($Policy.Identity) | $($Policy.DoNotAllowClickThrough) |`n")
                }
            }
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("Some Safe Links policies allow click-through, which reduces protection.`n`n")
            $null = $Result.Append("**Failed Policies:** $($FailedPolicies.Count) | **Passed Policies:** $($PassedPolicies.Count)`n`n")
            $null = $Result.Append("### Non-Compliant Policies`n`n")
            $null = $Result.Append("| Policy Name | DoNotAllowClickThrough | Recommended |`n")
            $null = $Result.Append("|------------|----------------------|-------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.DoNotAllowClickThrough) | true |`n")
            }
            $null = $Result.Append("`n**Remediation:** Disable click-through (set DoNotAllowClickThrough to true) to prevent users from bypassing Safe Links protection.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
