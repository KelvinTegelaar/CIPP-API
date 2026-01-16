function Invoke-CippTestORCA113 {
    <#
    .SYNOPSIS
    AllowClickThrough is disabled in Safe Links policies
    #>
    param($Tenant)

    try {
        $SafeLinksPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        $FailedPolicies = @()
        $PassedPolicies = @()

        foreach ($Policy in $SafeLinksPolicies) {
            # Check if DoNotAllowClickThrough is set to true (which means AllowClickThrough is disabled)
            if ($Policy.DoNotAllowClickThrough -eq $true) {
                $PassedPolicies += $Policy
            } else {
                $FailedPolicies += $Policy
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All Safe Links policies have click-through disabled (DoNotAllowClickThrough = true).`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)`n`n"
            if ($PassedPolicies.Count -gt 0) {
                $Result += "| Policy Name | DoNotAllowClickThrough |`n"
                $Result += "|------------|----------------------|`n"
                foreach ($Policy in $PassedPolicies) {
                    $Result += "| $($Policy.Identity) | $($Policy.DoNotAllowClickThrough) |`n"
                }
            }
        } else {
            $Status = 'Failed'
            $Result = "Some Safe Links policies allow click-through, which reduces protection.`n`n"
            $Result += "**Failed Policies:** $($FailedPolicies.Count) | **Passed Policies:** $($PassedPolicies.Count)`n`n"
            $Result += "### Non-Compliant Policies`n`n"
            $Result += "| Policy Name | DoNotAllowClickThrough | Recommended |`n"
            $Result += "|------------|----------------------|-------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.DoNotAllowClickThrough) | true |`n"
            }
            $Result += "`n**Remediation:** Disable click-through (set DoNotAllowClickThrough to true) to prevent users from bypassing Safe Links protection."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
