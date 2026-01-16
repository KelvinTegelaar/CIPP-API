function Invoke-CippTestORCA108 {
    <#
    .SYNOPSIS
    DKIM signing is set up for all your custom domains
    #>
    param($Tenant)

    try {
        $DkimConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $DkimConfig -or -not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
            return
        }

        # Get custom domains (exclude default .onmicrosoft.com domains)
        $CustomDomains = $AcceptedDomains | Where-Object {
            $_.DomainName -notlike '*.onmicrosoft.com' -and
            $_.DomainName -notlike '*.mail.onmicrosoft.com'
        }

        if ($CustomDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No custom domains configured. DKIM check not applicable for default domains only.'
        } else {
            $DomainsWithoutDkim = @()
            $DomainsWithDkim = @()

            foreach ($Domain in $CustomDomains) {
                $DkimForDomain = $DkimConfig | Where-Object { $_.Domain -eq $Domain.DomainName }

                if ($DkimForDomain -and $DkimForDomain.Enabled -eq $true) {
                    $DomainsWithDkim += $Domain.DomainName
                } else {
                    $DomainsWithoutDkim += $Domain.DomainName
                }
            }

            if ($DomainsWithoutDkim.Count -eq 0) {
                $Status = 'Passed'
                $Result = "DKIM signing is enabled for all custom domains ($($DomainsWithDkim.Count) domains).`n`n"
                $Result += "**Domains with DKIM enabled:**`n"
                $Result += ($DomainsWithDkim | ForEach-Object { "- $_" }) -join "`n"
            } else {
                $Status = 'Failed'
                $Result = "DKIM signing is not configured for all custom domains.`n`n"
                $Result += "**Missing DKIM:** $($DomainsWithoutDkim.Count) | **Configured:** $($DomainsWithDkim.Count)`n`n"
                $Result += "### Domains without DKIM:`n"
                $Result += ($DomainsWithoutDkim | ForEach-Object { "- $_" }) -join "`n"
                $Result += "`n`n**Remediation:** Enable DKIM signing for all custom domains to prevent email spoofing."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA108' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DKIM signing is set up for all your custom domains' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'DKIM'
    }
}
