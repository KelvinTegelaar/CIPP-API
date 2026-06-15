function Invoke-CippTestORCA235 {
    <#
    .SYNOPSIS
    SPF records setup for custom domains
    #>
    param($Tenant)

    try {
        $Results = Get-CIPPDomainAnalyser -TenantFilter $Tenant

        if (-not $Results) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Domain Analyser results found for this tenant. Run the CIPP Domain Analyser to populate domain health data.' -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'
            return
        }

        # ORCA scopes this to custom domains; onmicrosoft.com is handled by Microsoft.
        $CustomDomains = $Results | Where-Object { $_.Domain -notlike '*.onmicrosoft.com' }

        if (-not $CustomDomains -or $CustomDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('No custom domains found. Only onmicrosoft.com in use.')
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'
            return
        }

        $FailedDomains = [System.Collections.Generic.List[object]]::new()
        $PassedDomains = [System.Collections.Generic.List[object]]::new()

        foreach ($Domain in $CustomDomains) {
            # Valid SPF must start with v=spf1 AND end with -all (hard fail).
            # ~all (soft fail), ?all (neutral), and +all (pass all) are insufficient.
            # Third-party includes/IPs (Mimecast/Proofpoint/marketing) are fine alongside -all.
            $Spf = [string]$Domain.ActualSPFRecord
            $HasSpf = $Spf -match 'v=spf1'
            $HasHardFail = $Spf -match '-all\s*$'

            if ($HasSpf -and $HasHardFail) {
                $PassedDomains.Add($Domain) | Out-Null
            } else {
                $FailedDomains.Add($Domain) | Out-Null
            }
        }

        if ($FailedDomains.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All $($PassedDomains.Count) custom domains have a valid SPF record ending in -all.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedDomains.Count) of $($CustomDomains.Count) custom domains are missing a valid SPF record or do not end in -all (hard fail).`n`n")
            $null = $Result.Append("| Domain | SPF Record |`n| :----- | :--------- |`n")
            foreach ($Domain in ($FailedDomains | Select-Object -First 25)) {
                $Display = if ([string]::IsNullOrWhiteSpace($Domain.ActualSPFRecord)) { '*(none)*' } else { $Domain.ActualSPFRecord }
                $null = $Result.Append("| $($Domain.Domain) | $Display |`n")
            }
            $null = $Result.Append("`n**Remediation:** Publish an SPF TXT record ending in `-all` (hard fail). For Microsoft 365 only: `v=spf1 include:spf.protection.outlook.com -all`. If routing through a third-party gateway, include that provider alongside (e.g. Mimecast, Proofpoint, marketing services), but keep `-all` at the end. Avoid `~all`, `?all`, and especially `+all`.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA235' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SPF records setup for custom domains' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Configuration'
    }
}
