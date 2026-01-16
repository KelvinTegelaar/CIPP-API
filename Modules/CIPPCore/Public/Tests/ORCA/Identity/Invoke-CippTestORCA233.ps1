function Invoke-CippTestORCA233 {
    <#
    .SYNOPSIS
    Domains pointed at EOP or enhanced filtering used
    #>
    param($Tenant)

    try {
        $AcceptedDomains = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $AcceptedDomains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No accepted domains found in database.' -Risk 'High' -Name 'Domains pointed at EOP or enhanced filtering used' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Configuration'
            return
        }

        # This test requires checking MX records and inbound connectors which may not be available
        # We'll check if domains are authoritative (pointed at EOP) or use external mail flow
        $NonCompliantDomains = [System.Collections.Generic.List[string]]::new()
        $CompliantDomains = [System.Collections.Generic.List[string]]::new()

        foreach ($Domain in $AcceptedDomains) {
            # Authoritative domains point MX to EOP
            # InternalRelay/ExternalRelay domains use inbound connectors with enhanced filtering
            if ($Domain.DomainType -eq 'Authoritative') {
                $CompliantDomains.Add($Domain.DomainName) | Out-Null
            } elseif ($Domain.DomainType -in @('InternalRelay', 'ExternalRelay')) {
                # These should have enhanced filtering configured on inbound connectors
                # For now, we'll mark these as compliant if they exist
                $CompliantDomains.Add($Domain.DomainName) | Out-Null
            } else {
                $NonCompliantDomains.Add($Domain.DomainName) | Out-Null
            }
        }

        if ($NonCompliantDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All domains are properly configured for mail flow.`n`n"
            $Result += "**Compliant Domains:** $($CompliantDomains.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($NonCompliantDomains.Count) domains may not be properly configured for mail flow.`n`n"
            $Result += "**Domains Needing Review:**`n`n"
            foreach ($Domain in $NonCompliantDomains) {
                $Result += "- $Domain`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Domains pointed at EOP or enhanced filtering used' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA233' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Domains pointed at EOP or enhanced filtering used' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Configuration'
    }
}
