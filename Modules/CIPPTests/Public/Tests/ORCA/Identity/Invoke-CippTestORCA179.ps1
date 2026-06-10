function Invoke-CippTestORCA179 {
    <#
    .SYNOPSIS
    Safe Links is enabled intra-organization
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        # Exclude the Built-In Protection preset — Microsoft scopes it to external senders by design.
        $CustomPolicies = $Policies | Where-Object {
            $_.IsBuiltInProtection -ne $true
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $CustomPolicies) {
            if ($Policy.EnableForInternalSenders -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($PassedPolicies.Count -gt 0 -and $FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All custom Safe Links policies are enabled for internal senders.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } elseif ($PassedPolicies.Count -eq 0 -and $FailedPolicies.Count -eq 0) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("No custom Safe Links policies are configured. The Built-In Protection policy does not cover internal senders.`n`n**Remediation:** Create a custom Safe Links policy with `EnableForInternalSenders = `$true`.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) Safe Links policies are not enabled for internal senders.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Enable For Internal Senders |`n")
            $null = $Result.Append("|------------|----------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.EnableForInternalSenders) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA179' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Safe Links is enabled intra-organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
