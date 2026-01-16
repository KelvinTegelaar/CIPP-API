function Invoke-CippTestORCA112 {
    <#
    .SYNOPSIS
    Anti-spoofing protection action is configured to Move message to Junk Email folders
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA112' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Anti-spoofing protection action configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.AuthenticationFailAction -eq 'MoveToJmf') {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All anti-phishing policies have anti-spoofing action set to Move to Junk Email folder.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-phishing policies do not have anti-spoofing action set to Move to Junk Email folder.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Authentication Fail Action |`n"
            $Result += "|------------|---------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Identity) | $($Policy.AuthenticationFailAction) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA112' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Anti-spoofing protection action configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA112' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Anti-spoofing protection action configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Anti-Phish'
    }
}
