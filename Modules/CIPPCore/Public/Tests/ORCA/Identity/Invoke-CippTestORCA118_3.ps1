function Invoke-CippTestORCA118_3 {
    <#
    .SYNOPSIS
    Own domains not allow listed in Anti-Spam
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Own domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Own domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
            return
        }

        $OwnDomains = $AcceptedDomains | Select-Object -ExpandProperty DomainName
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            $HasOwnDomainInAllowList = $false

            if ($Policy.AllowedSenderDomains) {
                foreach ($AllowedDomain in $Policy.AllowedSenderDomains) {
                    if ($OwnDomains -contains $AllowedDomain) {
                        $HasOwnDomainInAllowList = $true
                        break
                    }
                }
            }

            if ($HasOwnDomainInAllowList) {
                $FailedPolicies.Add($Policy) | Out-Null
            } else {
                $PassedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No anti-spam policies have own domains in the allow list.`n`n"
            $Result += "**Compliant Policies:** $($PassedPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedPolicies.Count) anti-spam policies have own domains in the allow list.`n`n"
            $Result += "**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n"
            $Result += "| Policy Name | Own Domains in Allow List |`n"
            $Result += "|------------|---------------------------|`n"
            foreach ($Policy in $FailedPolicies) {
                $OwnDomainsInList = $Policy.AllowedSenderDomains | Where-Object { $OwnDomains -contains $_ }
                $Result += "| $($Policy.Identity) | $($OwnDomainsInList -join ', ') |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Own domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Own domains not allow listed in Anti-Spam' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Anti-Spam'
    }
}
