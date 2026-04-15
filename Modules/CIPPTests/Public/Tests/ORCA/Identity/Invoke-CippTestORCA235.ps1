function Invoke-CippTestORCA235 {
    <#
    .SYNOPSIS
    SPF records setup for custom domains
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'
            return
        }

        # Note: This test would ideally check DNS SPF records
        # Since we don't have DNS query capability here, we'll provide informational guidance

        $CustomDomains = $AcceptedDomains | Where-Object { $_.DomainName -notlike '*.onmicrosoft.com' }

        if ($CustomDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No custom domains found. Only using onmicrosoft.com domain.`n`n"
            $Result += "**Total Domains:** $($AcceptedDomains.Count)"
        } else {
            $Status = 'Informational'
            $Result = "Found $($CustomDomains.Count) custom domains that should have SPF records configured.`n`n"
            $Result += "**Custom Domains:**`n`n"
            foreach ($Domain in $CustomDomains) {
                $Result += "- $($Domain.DomainName)`n"
            }
            $Result += "`n**Action Required:** Verify that each custom domain has an SPF record including Microsoft 365:`n"
            $Result += "``v=spf1 include:spf.protection.outlook.com -all``"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'
    }
}
