function Invoke-CippTestCIS_2_1_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.8) - SPF records SHALL be published for all Exchange Domains
    #>
    param($Tenant)

    try {
        $Results = Get-CIPPDomainAnalyser -TenantFilter $Tenant

        if (-not $Results) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_8' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Domain Analyser results found for this tenant. Run the CIPP Domain Analyser to populate domain health data.' -Risk 'High' -Name 'SPF records are published for all Exchange Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        $Failing = $Results | Where-Object { [string]::IsNullOrWhiteSpace($_.ActualSPFRecord) -or $_.ActualSPFRecord -notmatch 'v=spf1' }

        if (-not $Failing -or $Failing.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Results.Count) domain(s) have an SPF record published."
        } else {
            $Status = 'Failed'
            $Result = "$($Failing.Count) of $($Results.Count) domain(s) are missing a valid SPF record:`n`n| Domain | SPF Record |`n| :----- | :--------- |`n"
            foreach ($D in ($Failing | Select-Object -First 25)) {
                $Result += "| $($D.Domain) | $($D.ActualSPFRecord) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_8' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SPF records are published for all Exchange Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_8' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SPF records are published for all Exchange Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}
