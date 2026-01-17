function Invoke-CippTestORCA103 {
    <#
    .SYNOPSIS
    Outbound spam filter policy settings configured
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedOutboundSpamFilterPolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA103' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Outbound spam filter policy settings configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $IsCompliant = $true
            $Issues = [System.Collections.Generic.List[string]]::new()

            if ($Policy.RecipientLimitExternalPerHour -ne 500) {
                $IsCompliant = $false
                $Issues.Add("RecipientLimitExternalPerHour: $($Policy.RecipientLimitExternalPerHour) (should be 500)") | Out-Null
            }
            if ($Policy.RecipientLimitInternalPerHour -ne 1000) {
                $IsCompliant = $false
                $Issues.Add("RecipientLimitInternalPerHour: $($Policy.RecipientLimitInternalPerHour) (should be 1000)") | Out-Null
            }
            if ($Policy.ActionWhenThresholdReached -ne 'BlockUserForToday') {
                $IsCompliant = $false
                $Issues.Add("ActionWhenThresholdReached: $($Policy.ActionWhenThresholdReached) (should be BlockUserForToday)") | Out-Null
            }

            if ($IsCompliant) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add([PSCustomObject]@{
                        Policy = $Policy
                        Issues = $Issues
                    }) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All outbound spam filter policies are configured correctly.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) outbound spam filter policies are not configured correctly.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Issues |`n"
            $Result += "|------------|--------|`n"
            foreach ($Failed in $FailedPolicies) {
                $Result += "| $($Failed.Policy.Identity) | $($Failed.Issues -join '<br/>') |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA103' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Outbound spam filter policy settings configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'

        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA103' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Outbound spam filter policy settings configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Anti-Spam'
        }
    }
