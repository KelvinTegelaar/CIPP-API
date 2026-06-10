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

        # Exclude the Built-In Protection preset — Microsoft owns it and intentionally allows click-through on the baseline.
        $CustomPolicies = $SafeLinksPolicies | Where-Object {
            $_.IsBuiltInProtection -ne $true
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $CustomPolicies) {
            if ($Policy.AllowClickThrough -eq $false) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($PassedPolicies.Count -gt 0 -and $FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All custom Safe Links policies have click-through disabled (AllowClickThrough = false).`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | AllowClickThrough |`n")
            $null = $Result.Append("|------------|-------------------|`n")
            foreach ($Policy in $PassedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.AllowClickThrough) |`n")
            }
        } elseif ($PassedPolicies.Count -eq 0 -and $FailedPolicies.Count -eq 0) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("No custom Safe Links policies are configured. The Built-In Protection policy allows click-through by design.`n`n**Remediation:** Create a custom Safe Links policy with `AllowClickThrough = `$false`.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) custom Safe Links policies allow click-through, which reduces protection.`n`n")
            $null = $Result.Append("**Failed Policies:** $($FailedPolicies.Count) | **Passed Policies:** $($PassedPolicies.Count)`n`n")
            $null = $Result.Append("### Non-Compliant Policies`n`n")
            $null = $Result.Append("| Policy Name | AllowClickThrough | Recommended |`n")
            $null = $Result.Append("|------------|-------------------|-------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.AllowClickThrough) | false |`n")
            }
            $null = $Result.Append("`n**Remediation:** Set AllowClickThrough to false to prevent users from bypassing Safe Links protection.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA113' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'AllowClickThrough is disabled in Safe Links policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
