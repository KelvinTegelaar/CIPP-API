function Invoke-CippTestORCA231 {
    <#
    .SYNOPSIS
    Each domain has an anti-spam policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $ContentFilterPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'
            return
        }

        if (-not $ContentFilterPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No anti-spam policies found. Each domain should have an anti-spam policy.' -Risk 'High' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'
            return
        }

        # Get all recipient domains from policies
        $CoveredDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $ContentFilterPolicies) {
            if ($Policy.RecipientDomainIs) {
                foreach ($Domain in $Policy.RecipientDomainIs) {
                    $CoveredDomains.Add($Domain) | Out-Null
                }
            }
        }

        $DomainsWithoutPolicy = [System.Collections.Generic.List[string]]::new()
        foreach ($Domain in $AcceptedDomains) {
            if ($CoveredDomains -notcontains $Domain.DomainName) {
                $DomainsWithoutPolicy.Add($Domain.DomainName) | Out-Null
            }
        }

        if ($DomainsWithoutPolicy.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All accepted domains are covered by anti-spam policies.`n`n"
            $Result += "**Total Accepted Domains:** $($AcceptedDomains.Count)`n"
            $Result += "**Total Anti-spam Policies:** $($ContentFilterPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($DomainsWithoutPolicy.Count) domains do not have an anti-spam policy.`n`n"
            $Result += "**Domains Without Policy:**`n`n"
            foreach ($Domain in $DomainsWithoutPolicy) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA231' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has an anti-spam policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Spam'
    }
}
