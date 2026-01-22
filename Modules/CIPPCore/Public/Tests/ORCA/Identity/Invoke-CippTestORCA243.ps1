function Invoke-CippTestORCA243 {
    <#
    .SYNOPSIS
    Authenticated Receive Chain for non-EOP domains
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA243' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'Medium' -Name 'Authenticated Receive Chain for non-EOP domains' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Configuration'
            return
        }

        # Check for non-authoritative domains that would need inbound connectors
        $NonAuthDomains = $AcceptedDomains | Where-Object { $_.DomainType -in @('InternalRelay', 'ExternalRelay') }

        if ($NonAuthDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All domains are authoritative. No inbound connectors needed.`n`n"
            $Result += "**Total Domains:** $($AcceptedDomains.Count)"
        } else {
            $Status = 'Informational'
            $Result = "Found $($NonAuthDomains.Count) non-authoritative domains.`n`n"
            $Result += "**Domains Requiring Inbound Connectors:**`n`n"
            foreach ($Domain in $NonAuthDomains) {
                $Result += "- $($Domain.DomainName) (Type: $($Domain.DomainType))`n"
            }
            $Result += "`n**Action Required:** Verify inbound connectors are configured with proper authentication for these domains"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA243' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authenticated Receive Chain for non-EOP domains' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA243' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authenticated Receive Chain for non-EOP domains' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Configuration'
    }
}
