function Invoke-CippTestCIS_1_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.1) - Password expiration policy SHALL be set to 'never expire'
    #>
    param($Tenant)

    try {
        $Domains = Get-CIPPTestData -TenantFilter $Tenant -Type 'Domains'

        if (-not $Domains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Domains cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'Password expiration policy' is set to never expire" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
            return
        }

        $Failing = $Domains | Where-Object { $_.passwordValidityPeriodInDays -lt 2147483647 -and $_.passwordValidityPeriodInDays -gt 0 }

        if (-not $Failing -or $Failing.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Domains.Count) domain(s) have password expiration disabled (passwordValidityPeriodInDays = 2147483647)."
        } else {
            $Status = 'Failed'
            $Result = "$($Failing.Count) domain(s) still expire passwords:`n`n| Domain | Validity (days) |`n| :----- | :-------------- |`n"
            foreach ($D in $Failing) {
                $Result += "| $($D.id) | $($D.passwordValidityPeriodInDays) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Password expiration policy' is set to never expire" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Password expiration policy' is set to never expire" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    }
}
