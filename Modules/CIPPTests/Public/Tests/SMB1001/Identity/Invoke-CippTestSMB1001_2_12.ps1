function Invoke-CippTestSMB1001_2_12 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.12) - Email Authentication and Anti-Spoofing (SPF, DKIM, DMARC)

    .DESCRIPTION
    Verifies SPF, DKIM and DMARC are configured on every accepted sending domain. Combines
    Domain Analyser results (SPF, DMARC) with Exchange DKIM signing config. Level 3 prescribes
    DMARC p=reject or p=quarantine and 2048-bit DKIM keys.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_12'
    $Name = 'SPF, DKIM, and DMARC are configured on all sending domains'

    try {
        $Analyser = Get-CIPPDomainAnalyser -TenantFilter $Tenant
        $Dkim = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoDkimSigningConfig'
        $Accepted = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAcceptedDomains'

        if (-not $Analyser -or -not $Accepted) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required data (Domain Analyser or ExoAcceptedDomains) not found. Run the CIPP Domain Analyser and refresh caches.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
            return
        }

        $Sending = @($Accepted | Where-Object { -not $_.SendingFromDomainDisabled -and $_.DomainName -notlike '*onmicrosoft.com' })

        $Failures = @(
            foreach ($D in $Sending) {
                $A = $Analyser | Where-Object { $_.Domain -eq $D.DomainName } | Select-Object -First 1
                $K = $Dkim | Where-Object { $_.Domain -eq $D.DomainName } | Select-Object -First 1
                $Spf = $A.ActualSPFRecord -match 'v=spf1'
                $Dmarc = $A.DMARCRecord -match 'v=DMARC1'
                $DmarcStrong = $A.DMARCRecord -match 'p=(reject|quarantine)'
                $DkimEnabled = ($K -and $K.Enabled -eq $true)
                $DomainIssues = @(
                    if (-not $Spf) { 'no SPF' }
                    if (-not $DkimEnabled) { 'no DKIM' }
                    if (-not $Dmarc) { 'no DMARC' }
                    elseif (-not $DmarcStrong) { 'DMARC weak (not p=reject/quarantine)' }
                )
                if ($DomainIssues.Count -gt 0) {
                    [PSCustomObject]@{
                        Domain = $D.DomainName
                        SPF    = if ($Spf) { '✅' } else { '❌' }
                        DKIM   = if ($DkimEnabled) { '✅' } else { '❌' }
                        DMARC  = if ($Dmarc) { if ($DmarcStrong) { '✅' } else { '⚠️' } } else { '❌' }
                        Issues = $DomainIssues -join ', '
                    }
                }
            }
        )

        if ($Sending.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No custom sending domains configured.'
        } elseif ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Sending.Count) sending domain(s) have SPF, DKIM, and DMARC (p=reject or p=quarantine) configured."
        } else {
            $Status = 'Failed'
            $TableRows = foreach ($F in ($Failures | Select-Object -First 25)) {
                "| $($F.Domain) | $($F.SPF) | $($F.DKIM) | $($F.DMARC) | $($F.Issues) |"
            }
            $Result = (@(
                    "$($Failures.Count) of $($Sending.Count) sending domain(s) are missing email authentication:"
                    ''
                    '| Domain | SPF | DKIM | DMARC | Issues |'
                    '| :----- | :-: | :--: | :---: | :----- |'
                ) + $TableRows) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Authentication'
    }
}
