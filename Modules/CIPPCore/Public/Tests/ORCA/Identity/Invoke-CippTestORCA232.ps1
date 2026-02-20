function Invoke-CippTestORCA232 {
    <#
    .SYNOPSIS
    Each domain has a malware filter policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $MalwarePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'
            return
        }

        if (-not $MalwarePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No malware filter policies found. Each domain should have a malware filter policy.' -Risk 'High' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'
            return
        }

        # Get all recipient domains from policies
        $CoveredDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $MalwarePolicies) {
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
            $Result = "All accepted domains are covered by malware filter policies.`n`n"
            $Result += "**Total Accepted Domains:** $($AcceptedDomains.Count)`n"
            $Result += "**Total Malware Filter Policies:** $($MalwarePolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($DomainsWithoutPolicy.Count) domains do not have a malware filter policy.`n`n"
            $Result += "**Domains Without Policy:**`n`n"
            foreach ($Domain in $DomainsWithoutPolicy) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA232' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has a malware filter policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Malware'
    }
}
