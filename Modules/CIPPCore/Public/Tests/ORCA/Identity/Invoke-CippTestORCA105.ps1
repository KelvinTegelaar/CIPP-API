function Invoke-CippTestORCA105 {
    <#
    .SYNOPSIS
    Safe Links Synchronous URL detonation is enabled
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA105' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Safe Links Synchronous URL detonation is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.DeliverMessageAfterScan -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All Safe Links policies have synchronous URL detonation enabled.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) Safe Links policies do not have synchronous URL detonation enabled.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Deliver Message After Scan |`n"
            $Result += "|------------|---------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.DeliverMessageAfterScan) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA105' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Links Synchronous URL detonation is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA105' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Links Synchronous URL detonation is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
