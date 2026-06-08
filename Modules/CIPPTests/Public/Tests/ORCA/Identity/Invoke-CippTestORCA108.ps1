function Invoke-CippTestORCA108 {
    <#
    .SYNOPSIS
    DKIM signing is set up for all your custom domains
    #>
    param($Tenant)

    try {
        $DkimConfig = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $AcceptedDomains = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $DkimConfig -or -not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
            return
        }

        $CustomDomains = $AcceptedDomains.Where({
            $_.DomainName -notlike '*.onmicrosoft.com' -and
            $_.DomainName -notlike '*.mail.onmicrosoft.com'
        })

        if ($CustomDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No custom domains configured. DKIM check not applicable for default domains only.'
        } else {
            $DkimByDomain = $DkimConfig | Group-Object Domain -AsHashTable -AsString
            $DomainsWithoutDkim = [System.Collections.Generic.List[string]]::new()
            $DomainsWithDkim = [System.Collections.Generic.List[string]]::new()

            foreach ($Domain in $CustomDomains) {
                $DkimForDomain = $null
                if ($DkimByDomain -and $DkimByDomain.ContainsKey($Domain.DomainName)) { $DkimForDomain = @($DkimByDomain[$Domain.DomainName])[0] }

                if ($DkimForDomain -and $DkimForDomain.Enabled -eq $true) {
                    $DomainsWithDkim.Add($Domain.DomainName)
                } else {
                    $DomainsWithoutDkim.Add($Domain.DomainName)
                }
            }

            if ($DomainsWithoutDkim.Count -eq 0) {
                $Status = 'Passed'
                $sb = [System.Text.StringBuilder]::new()
                $null = $sb.Append("DKIM signing is enabled for all custom domains ($($DomainsWithDkim.Count) domains).`n`n")
                $null = $sb.Append("**Domains with DKIM enabled:**`n")
                $null = $sb.Append(($DomainsWithDkim | ForEach-Object { "- $_" }) -join "`n")
                $Result = $sb.ToString()
            } else {
                $Status = 'Failed'
                $sb = [System.Text.StringBuilder]::new()
                $null = $sb.Append("DKIM signing is not configured for all custom domains.`n`n")
                $null = $sb.Append("**Missing DKIM:** $($DomainsWithoutDkim.Count) | **Configured:** $($DomainsWithDkim.Count)`n`n")
                $null = $sb.Append("### Domains without DKIM:`n")
                $null = $sb.Append(($DomainsWithoutDkim | ForEach-Object { "- $_" }) -join "`n")
                $null = $sb.Append("`n`n**Remediation:** Enable DKIM signing for all custom domains to prevent email spoofing.")
                $Result = $sb.ToString()
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
    }
}
