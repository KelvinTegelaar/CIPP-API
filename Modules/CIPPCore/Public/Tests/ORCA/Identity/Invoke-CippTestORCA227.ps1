function Invoke-CippTestORCA227 {
    <#
    .SYNOPSIS
    Each domain has a Safe Attachments policy
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'
        $SafeAttachmentPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA227' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Each domain has a Safe Attachments policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Attachments'
            return
        }

        if (-not $SafeAttachmentPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA227' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Safe Attachments policies found. Each domain should have a Safe Attachments policy.' -Risk 'High' -Name 'Each domain has a Safe Attachments policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Attachments'
            return
        }

        # Get all recipient domains from policies
        $CoveredDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $SafeAttachmentPolicies) {
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
            $Result = "All accepted domains are covered by Safe Attachments policies.`n`n"
            $Result += "**Total Accepted Domains:** $($AcceptedDomains.Count)`n"
            $Result += "**Total Safe Attachments Policies:** $($SafeAttachmentPolicies.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($DomainsWithoutPolicy.Count) domains do not have a Safe Attachments policy.`n`n"
            $Result += "**Domains Without Policy:**`n`n"
            foreach ($Domain in $DomainsWithoutPolicy) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA227' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Each domain has a Safe Attachments policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA227' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Each domain has a Safe Attachments policy' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Safe Attachments'
    }
}
