function Invoke-CippTestORCA230 {
    <#
    .SYNOPSIS
    Each domain has an Anti-phishing policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $AntiPhishPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA230' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has an Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Phish'
            return
        }

        if (-not $AntiPhishPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA230' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Anti-phishing policies found. Each domain should have an Anti-phishing policy.' -Risk 'High' -Name 'Each domain has an Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Phish'
            return
        }

        # Get all recipient domains from policies
        $CoveredDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $AntiPhishPolicies) {
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
            $Result = "All accepted domains are covered by Anti-phishing policies.`n`n"
            $Result += "**Total Accepted Domains:** $($AcceptedDomains.Count)`n"
            $Result += "**Total Anti-phishing Policies:** $($AntiPhishPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($DomainsWithoutPolicy.Count) domains do not have an Anti-phishing policy.`n`n"
            $Result += "**Domains Without Policy:**`n`n"
            foreach ($Domain in $DomainsWithoutPolicy) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA230' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has an Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Phish'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA230' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has an Anti-phishing policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Anti-Phish'
    }
}
