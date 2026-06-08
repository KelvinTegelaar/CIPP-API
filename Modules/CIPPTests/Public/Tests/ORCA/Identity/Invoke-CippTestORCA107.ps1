function Invoke-CippTestORCA107 {
    <#
    .SYNOPSIS
    End-user spam notification is enabled
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoQuarantinePolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.EndUserSpamNotificationFrequency -gt 0) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0 -and $PassedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All quarantine policies have end-user spam notifications enabled.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Notification Frequency (days) |`n")
            $null = $Result.Append("|------------|-------------------------------|`n")
            foreach ($Policy in $PassedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.EndUserSpamNotificationFrequency) |`n")
            }
        } elseif ($PassedPolicies.Count -eq 0) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("No quarantine policies have end-user spam notifications enabled.`n`n")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) quarantine policies do not have end-user spam notifications enabled.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Notification Frequency |`n")
            $null = $Result.Append("|------------|----------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | Disabled |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA107' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'End-user spam notification is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Quarantine'
    }
}
