function Invoke-CippTestORCA226 {
    <#
    .SYNOPSIS
    Each domain has a Safe Links policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $SafeLinksPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
            return
        }

        if (-not $SafeLinksPolicies) {
            if (-not (Test-CIPPStandardLicense -StandardName 'ORCA226' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Safe Links policies found. Each domain should have a Safe Links policy.' -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
            }
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
            $Result = [System.Text.StringBuilder]::new("All accepted domains are covered by Safe Links policies.`n`n")
            $null = $Result.Append("**Total Accepted Domains:** $($AcceptedDomains.Count)`n")
            $null = $Result.Append("**Total Safe Links Policies:** $($SafeLinksPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($DomainsWithoutPolicy.Count) domains do not have a Safe Links policy.`n`n")
            $null = $Result.Append("**Domains Without Policy:**`n`n")
            foreach ($Domain in $DomainsWithoutPolicy) {
                $null = $Result.Append("- $Domain`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA226' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has a Safe Links policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Links'
    }
}
