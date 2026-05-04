function Invoke-CippTestCIS_2_1_10 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.10) - DMARC Records for all Exchange Online domains SHALL be published
    #>
    param($Tenant)

    try {
        $Results = Get-CIPPDomainAnalyser -TenantFilter $Tenant

        if (-not $Results) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_10' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Domain Analyser results found for this tenant. Run the CIPP Domain Analyser to populate domain health data.' -Risk 'High' -Name 'DMARC Records for all Exchange Online domains are published' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        # CIS expects a DMARC record with p=quarantine or p=reject
        $Acceptable = @('quarantine', 'reject')
        $Failing = $Results | Where-Object { $_.DMARCPresent -ne $true -or $_.DMARCActionPolicy -notin $Acceptable }

        if (-not $Failing -or $Failing.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Results.Count) domain(s) have a DMARC record with p=quarantine or p=reject."
        } else {
            $Status = 'Failed'
            $Result = "$($Failing.Count) of $($Results.Count) domain(s) are missing a compliant DMARC record:`n`n| Domain | DMARCPresent | DMARCActionPolicy |`n| :----- | :----------- | :---------------- |`n"
            foreach ($D in ($Failing | Select-Object -First 25)) {
                $Result += "| $($D.Domain) | $($D.DMARCPresent) | $($D.DMARCActionPolicy) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_10' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'DMARC Records for all Exchange Online domains are published' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_10' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'DMARC Records for all Exchange Online domains are published' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}
