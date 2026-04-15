function Invoke-CippTestORCA226 {
    <#
    .SYNOPSIS
    Each domain has a Safe Links policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $SafeLinksPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
            return
        }

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Safe Links policies found. Each domain should have a Safe Links policy.' -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
            return
        }

        # Get all recipient domains from policies
        $CoveredDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $SafeLinksPolicies) {
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
            $Result = "All accepted domains are covered by Safe Links policies.`n`n"
            $Result += "**Total Accepted Domains:** $($AcceptedDomains.Count)`n"
            $Result += "**Total Safe Links Policies:** $($SafeLinksPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($DomainsWithoutPolicy.Count) domains do not have a Safe Links policy.`n`n"
            $Result += "**Domains Without Policy:**`n`n"
            foreach ($Domain in $DomainsWithoutPolicy) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
    }
}
