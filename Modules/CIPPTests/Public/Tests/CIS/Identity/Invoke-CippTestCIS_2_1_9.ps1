function Invoke-CippTestCIS_2_1_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.9) - DKIM SHALL be enabled for all Exchange Online Domains
    #>
    param($Tenant)

    try {
        $Dkim = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $Accepted = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $Dkim -or -not $Accepted) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ExoDkimSigningConfig or ExoAcceptedDomains) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        $Sending = $Accepted.Where({ -not $_.SendingFromDomainDisabled -and $_.DomainName -notlike '*onmicrosoft.com' })
        $DkimByDomain = $Dkim | Group-Object Domain -AsHashTable -AsString
        $Failed = [System.Collections.Generic.List[object]]::new()
        foreach ($D in $Sending) {
            $Cfg = $null
            if ($DkimByDomain.ContainsKey($D.DomainName)) { $Cfg = @($DkimByDomain[$D.DomainName])[0] }
            if (-not $Cfg -or $Cfg.Enabled -ne $true) {
                $Failed.Add([PSCustomObject]@{ Domain = $D.DomainName; Enabled = $Cfg.Enabled })
            }
        }

        if ($Failed.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("DKIM is enabled for all $($Sending.Count) sending domain(s).")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("DKIM is not enabled for $($Failed.Count) sending domain(s):`n`n| Domain | DKIM Enabled |`n| :----- | :----------- |`n")
            foreach ($F in $Failed) { $null = $Result.Append("| $($F.Domain) | $($F.Enabled) |`n") }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DKIM is enabled for all Exchange Online Domains' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}
