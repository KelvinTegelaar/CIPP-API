function Invoke-CippTestCIS_2_1_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.9) - DKIM SHALL be enabled for all Exchange Online Domains
    #>
    param($Tenant)

    try {
        $Dkim = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $Accepted = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $Dkim -or -not $Accepted) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ExoDkimSigningConfig or ExoAcceptedDomains) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        $Sending = $Accepted | Where-Object { -not $_.SendingFromDomainDisabled -and $_.DomainName -notlike '*onmicrosoft.com' }
        $Failed = @()
        foreach ($D in $Sending) {
            $Cfg = $Dkim | Where-Object { $_.Domain -eq $D.DomainName } | Select-Object -First 1
            if (-not $Cfg -or $Cfg.Enabled -ne $true) {
                $Failed += [PSCustomObject]@{ Domain = $D.DomainName; Enabled = $Cfg.Enabled }
            }
        }

        if ($Failed.Count -eq 0) {
            $Status = 'Passed'
            $Result = "DKIM is enabled for all $($Sending.Count) sending domain(s)."
        } else {
            $Status = 'Failed'
            $Result = "DKIM is not enabled for $($Failed.Count) sending domain(s):`n`n| Domain | DKIM Enabled |`n| :----- | :----------- |`n"
            foreach ($F in $Failed) { $Result += "| $($F.Domain) | $($F.Enabled) |`n" }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}
