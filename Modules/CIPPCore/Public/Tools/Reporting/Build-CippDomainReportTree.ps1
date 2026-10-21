function Build-CippDomainReportTree {
    <#
    .SYNOPSIS
        Compose the client-facing domain security assessment for every domain in a tenant as a component tree.
    .PARAMETER Data
        TenantName, IncludeDetails and Domains: one entry per tenant domain with Domain, Result (the stored Domain Analyser
        result, absent when the domain has not been analysed yet), Checks (the stored per-check DNSHealth messages) and
        DkimSelectors. Returns @{ Blocks; Variables }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $TenantName = [string]$Data.TenantName
    $DangerC = '#742A2A'; $WarnC = '#744210'; $GoodC = '#22543D'
    $Labels = @{ pass = 'Pass'; warn = 'Needs attention'; fail = 'Fail'; muted = 'Not checked' }
    $Short = @{ pass = 'Pass'; warn = 'Review'; fail = 'Fail'; muted = 'Unknown' }
    $IntuneLabel = @{ 'Correct' = 'Configured'; 'Legacy' = 'Legacy target'; 'No CNAME' = 'Not set up'; 'Error' = 'Not checked'; '' = 'Not checked' }
    $CheckOrder = 'DMARC', 'SPF', 'DKIM', 'MX', 'DNSSEC', 'MTA-STS'
    $Why = @{
        'DMARC'   = 'DMARC is what actually stops criminals sending email that appears to come from a domain. Without an enforcing policy, forged invoices and payment requests in the organisation''s name can land in the inboxes of customers and suppliers.'
        'SPF'     = 'SPF lets receiving mail systems check that a message came from a server the organisation has approved. A missing or broken record makes genuine mail more likely to be junked and forged mail more likely to be accepted.'
        'DKIM'    = 'DKIM signs outgoing mail so recipients can verify it is genuine and unchanged in transit. It is also what lets DMARC pass for mail sent through third-party services.'
        'MX'      = 'MX records decide where mail for a domain is delivered. If they are missing or wrong, mail is lost or routed somewhere it should not be.'
        'DNSSEC'  = 'DNSSEC protects a domain''s DNS answers, including every record in this report, from being tampered with on the way to the person looking them up.'
        'MTA-STS' = 'MTA-STS stops an attacker on the network from downgrading mail delivery to an unencrypted connection and reading messages in transit. TLS-RPT sends reports when that delivery fails.'
    }
    # The desired end state per check, added to the recommendations in the technical version only.
    $Target = @{
        'DMARC'   = 'v=DMARC1; p=reject; rua=mailto:<reporting address>, applied to all mail (pct=100 or omitted) with subdomains also at reject.'
        'SPF'     = 'One record such as v=spf1 include:<each sending service> -all, within 10 DNS lookups.'
        'DKIM'    = 'A valid key at every sending service''s selector, signing as the domain itself (selector1 and selector2 for Microsoft 365).'
        'MX'      = 'Records pointing at the mail service in use, or a Null MX (priority 0, host ".") for a domain that receives no mail.'
        'DNSSEC'  = 'A signed DNS zone with its DS record published at the registrar.'
        'MTA-STS' = 'A _mta-sts TXT record (v=STSv1; id=<change id>), a policy at https://mta-sts.<domain>/.well-known/mta-sts.txt with mode: enforce listing every MX host, and a _smtp._tls record (v=TLSRPTv1; rua=mailto:<address>).'
    }
    $Purpose = @{
        'DMARC'   = 'Tells other mail systems what to do with mail that fails SPF and DKIM.'
        'SPF'     = 'Lists the servers allowed to send email for the domain.'
        'DKIM'    = 'Adds a cryptographic signature that proves a message was not altered.'
        'MX'      = 'Directs incoming email to the right mail service.'
        'DNSSEC'  = 'Signs the domain''s DNS records so they cannot be forged.'
        'MTA-STS' = 'Requires other mail servers to use encryption when delivering mail.'
    }

    # Grade every domain once; the summary, the per-check sections and the technical pages all read from this.
    $Domains = foreach ($Entry in @($Data.Domains)) {
        $Domain = [string]$Entry.Domain
        $Result = $Entry.Result
        if (-not $Result) {
            [pscustomobject]@{ Domain = $Domain; Pending = $true; Score = -1 }
            continue
        }
        $Checks = $Entry.Checks
        $IsMicrosoftDomain = $Domain -like '*.onmicrosoft.com'
        $Selectors = @($Entry.DkimSelectors | Where-Object { $_ }) -join ', '

        $DmarcTone = if ([string]::IsNullOrEmpty($Result.DMARCPresent)) { 'muted' }
        elseif ($Result.DMARCPresent -ne $true -or $Result.DMARCActionPolicy -eq 'None') { 'fail' }
        elseif ($Result.DMARCActionPolicy -eq 'Reject' -and $Result.DMARCReportingActive -eq $true -and $Result.DMARCPercentagePass -eq $true) { 'pass' }
        else { 'warn' }
        $DmarcAdvice = if ($Result.DMARCPresent -ne $true) { 'Publish a DMARC policy and work towards enforcement.' }
        elseif ($Result.DMARCActionPolicy -eq 'None') { 'Move the policy from monitoring to enforcement.' }
        elseif ($Result.DMARCActionPolicy -in 'Quarantine', '') { 'Move the policy to full rejection.' }
        elseif ($Result.DMARCReportingActive -ne $true) { 'Turn on DMARC reporting.' }
        else { 'Apply the policy to all mail.' }
        # What made DMARC grade the way it did; DNSHealth does not flag a missing rua= or pct below 100 itself.
        $DmarcFinding = if ($Result.DMARCPresent -ne $true) { '' }
        elseif ($Result.DMARCActionPolicy -eq 'None') { 'The policy is monitor-only (p=none).' }
        elseif ($Result.DMARCActionPolicy -eq 'Quarantine') { 'The policy is p=quarantine.' }
        elseif ($Result.DMARCActionPolicy -ne 'Reject') { 'The domain and subdomain policies are not both p=reject.' }
        else {
            @(
                if ($Result.DMARCReportingActive -ne $true) { 'No aggregate report address (rua=) is set.' }
                if ($Result.DMARCPercentagePass -ne $true) { 'The policy applies to only part of the mail (pct below 100).' }
            ) -join ' '
        }
        $MtaSts = [string]$Result.MTASTS

        $Graded = @(
            @{ Name = 'DMARC'; Tone = $DmarcTone; Fix = $DmarcAdvice; Derived = $DmarcFinding; Action = 'Bring DMARC to an enforcing policy.' }
            @{ Name = 'SPF'; Tone = $(if ($Result.SPFPassAll -eq $true) { 'pass' } else { 'fail' }); Action = 'Publish a valid SPF record.'
                Fix = $(if ($Result.ScoreExplanation -match 'Multiple SPF') { 'Combine the SPF records into one.' } else { 'Publish a single valid SPF record covering every service that sends mail.' })
            }
            @{ Name = 'DKIM'; Tone = $(if ([string]::IsNullOrEmpty($Result.DKIMEnabled)) { 'muted' } elseif ($Result.DKIMEnabled -eq $true) { 'pass' } else { 'fail' }); Action = 'Enable DKIM signing.'
                Fix = 'Enable DKIM signing for every service that sends mail.'
            }
            @{ Name = 'MX'; Tone = $(if ($Result.MXPassTest -eq $true) { 'pass' } else { 'fail' }); Action = 'Correct the MX records.'
                Fix = 'Correct the MX records so mail reaches the right service.'
            }
            @{ Name = 'DNSSEC'; Hardening = $true; Tone = $(if ([string]::IsNullOrEmpty($Result.DNSSECPresent)) { 'muted' } elseif ($Result.DNSSECPresent -eq $true) { 'pass' } else { 'warn' }); Action = 'Enable DNSSEC.'
                Fix = 'Enable DNSSEC for the domain.'
            }
            @{ Name = 'MTA-STS'; Key = 'MTASTS'; Hardening = $true
                Tone = $(switch ($MtaSts) { 'Enforced' { 'pass' } { $_ -in 'Not configured', 'Testing', 'Invalid' } { 'warn' } default { 'muted' } })
                Label = $(switch ($MtaSts) { 'Testing' { 'Testing' } 'Invalid' { 'Invalid' } })
                Action = 'Enforce MTA-STS.'
                Fix = $(switch ($MtaSts) { 'Testing' { 'Move the policy from testing to enforcement.' } 'Invalid' { 'Correct the MTA-STS configuration.' } default { 'Publish an MTA-STS policy.' } })
            }
        )
        foreach ($g in $Graded) {
            if ($IsMicrosoftDomain -and $g.Hardening) {
                $g.NotApplicable = $true
                $g.Tone = 'muted'
                $g.Label = 'Managed by Microsoft'
            }
            if (-not $g.Label) { $g.Label = ($g.Hardening -and $g.Tone -eq 'warn') ? 'Recommended' : $Labels[$g.Tone] }
            $g.Cell = $g.NotApplicable ? 'N/A' : (($g.Hardening -and $g.Tone -eq 'warn') ? 'Advised' : $Short[$g.Tone])
            $Key = $g.Key ?? $g.Name
            $Stored = $Checks.$Key
            $g.Stored = $Stored
            $g.Findings = @(@($g.Derived) + @($Stored.Fails) + @($Stored.Warns) | Where-Object { $_ })
        }
        $Score = [int]$Result.ScorePercentage
        [pscustomobject]@{
            Domain            = $Domain
            Pending           = $false
            Result            = $Result
            Score             = $Score
            Band              = $(if ($Score -ge 80) { 'Good' } elseif ($Score -ge 50) { 'Needs attention' } else { 'At risk' })
            IsMicrosoftDomain = $IsMicrosoftDomain
            Selectors         = $Selectors
            Checks            = $Graded
            Analysed          = $(try { [datetime]$Result.LastRefresh } catch { $null })
        }
    }
    $Domains = @($Domains | Sort-Object -Property @{ Expression = 'Pending'; Descending = $false }, Score, Domain)
    $Analysed = @($Domains.Where({ -not $_.Pending }))
    $Pending = @($Domains.Where({ $_.Pending }))
    $Microsoft = @($Analysed.Where({ $_.IsMicrosoftDomain }))
    $Dates = @($Analysed.Analysed | Where-Object { $_ } | Sort-Object)
    $DateText = if (-not $Dates) { 'an unknown date' }
    elseif ($Dates[0].Date -eq $Dates[-1].Date) { $Dates[0].ToString('MMMM d, yyyy', [cultureinfo]'en-US') }
    else { '{0} to {1}' -f $Dates[0].ToString('MMMM d', [cultureinfo]'en-US'), $Dates[-1].ToString('MMMM d, yyyy', [cultureinfo]'en-US') }

    # One group per check: which domains fail, need attention, pass, are Microsoft-managed or could not be checked.
    $Groups = foreach ($Name in $CheckOrder) {
        $Rows = foreach ($d in $Analysed) { $c = $d.Checks.Where({ $_.Name -eq $Name }, 'First')[0]; [pscustomobject]@{ Domain = $d.Domain; Check = $c } }
        [pscustomobject]@{
            Name      = $Name
            Hardening = $Name -in 'DNSSEC', 'MTA-STS'
            ToFix     = @($Rows.Where({ $_.Check.Tone -in 'fail', 'warn' }) | Sort-Object { $_.Check.Tone -ne 'fail' }, Domain)
            Passing   = @($Rows.Where({ $_.Check.Tone -eq 'pass' }).ForEach({ $_.Domain }))
            Managed   = @($Rows.Where({ $_.Check.NotApplicable }).ForEach({ $_.Domain }))
            Unknown   = @($Rows.Where({ $_.Check.Tone -eq 'muted' -and -not $_.Check.NotApplicable }).ForEach({ $_.Domain }))
        }
    }
    $Average = if ($Analysed.Count) { [int][Math]::Round(($Analysed.Score | Measure-Object -Average).Average) } else { 0 }
    $Band = if ($Average -ge 80) { 'Good' } elseif ($Average -ge 50) { 'Needs attention' } else { 'At risk' }
    $BandCounts = @{ 'Good' = @($Analysed.Where({ $_.Band -eq 'Good' })).Count; 'Needs attention' = @($Analysed.Where({ $_.Band -eq 'Needs attention' })).Count; 'At risk' = @($Analysed.Where({ $_.Band -eq 'At risk' })).Count }
    $NeedWork = @($Groups.Where({ $_.ToFix.Count }))
    $Widest = @($NeedWork.Where({ -not $_.Hardening }) | Sort-Object { $_.ToFix.Count } -Descending)[0]
    $DomainWord = { param($n) if ($n -eq 1) { '1 domain' } else { "$n domains" } }

    $Summary = @(
        "We reviewed the public DNS records for the $(& $DomainWord $Domains.Count) in <b>$([System.Net.WebUtility]::HtmlEncode($TenantName))</b>, as recorded by the Domain Analyser on $DateText. These records decide whether other mail systems can tell genuine email from the organisation apart from forgeries."
        "$($BandCounts['Good']) $(if ($BandCounts['Good'] -eq 1) { 'is' } else { 'are' }) in good shape, $($BandCounts['Needs attention']) $(if ($BandCounts['Needs attention'] -eq 1) { 'needs' } else { 'need' }) attention and $($BandCounts['At risk']) $(if ($BandCounts['At risk'] -eq 1) { 'is' } else { 'are' }) at risk."
        $(if ($Widest) { "The most widespread gap is <b>$($Widest.Name)</b>, on $(& $DomainWord $Widest.ToFix.Count)." })
        $(if ($Microsoft.Count) { "$(& $DomainWord $Microsoft.Count) $(if ($Microsoft.Count -eq 1) { 'is a' } else { 'are' }) Microsoft-managed onmicrosoft.com $(if ($Microsoft.Count -eq 1) { 'domain' } else { 'domains' }), where Microsoft sets up SPF, DKIM and MX and only a DMARC record can be added, so DNSSEC and MTA-STS do not apply to $(if ($Microsoft.Count -eq 1) { 'it' } else { 'them' })." })
        $(if ($Pending.Count) { "$(& $DomainWord $Pending.Count) $(if ($Pending.Count -eq 1) { 'has' } else { 'have' }) not been analysed yet and $(if ($Pending.Count -eq 1) { 'is' } else { 'are' }) listed without results." })
    ) -join ' '
    $BandText = switch ($Band) {
        'Good' { 'Across the organisation, the core email protections are in place. The remaining items are improvements rather than gaps.' }
        'Needs attention' { 'Some core email protections are missing or incomplete on part of the organisation''s domains. Those domains can be impersonated more easily than they should be, and genuine mail is at greater risk of being junked.' }
        default { 'Key email protections are missing across the organisation''s domains. As it stands, they can be readily impersonated in phishing and invoice fraud, and recipients have little way to tell genuine mail from forgeries.' }
    }

    $Blocks = [System.Collections.Generic.List[object]]::new()

    $Blocks.Add((New-CippReportPage -Title 'Summary' -Subtitle "Email security and DNS configuration across $TenantName"))
    $Blocks.Add((New-CippReportParagraph -Html "<p>$Summary</p>"))
    $Blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = "$($Domains.Count)"; label = 'Domains' }
                @{ value = "$Average%"; label = 'Average Score'; colour = @{ 'Good' = $GoodC; 'Needs attention' = $WarnC; 'At risk' = $DangerC }[$Band] }
                @{ value = "$($BandCounts['Needs attention'] + $BandCounts['At risk'])"; label = 'Domains Needing Work'; colour = $(if ($BandCounts['Needs attention'] + $BandCounts['At risk']) { $WarnC }) }
                @{ value = "$($BandCounts['At risk'])"; label = 'At Risk'; colour = $(if ($BandCounts['At risk']) { $DangerC }) }
            )))
    $Blocks.Add($(switch ($Band) {
                'Good' { New-CippReportClearBox -Title "Overall: $Band" -Content $BandText }
                'Needs attention' { New-CippReportInfoBox -Title "Overall: $Band" -Tone warn -Content $BandText }
                default { New-CippReportAlertBox -Title "Overall: $Band" -Colour $DangerC -Content $BandText }
            }))
    $MatrixColumns = @(
        @{ header = 'Domain'; key = 'domain'; width = 2.6; bold = $true }
        @{ header = 'Score'; key = 'score'; width = 0.8; align = 'right' }
        foreach ($Name in $CheckOrder) { @{ header = $Name; key = "c$($Name -replace '\W')"; width = 0.95; toneField = "t$($Name -replace '\W')" } }
    )
    $MatrixRows = foreach ($d in $Domains) {
        $Row = @{ domain = $d.Domain; score = $(if ($d.Pending) { 'Pending' } else { "$($d.Score)%" }) }
        foreach ($Name in $CheckOrder) {
            $k = $Name -replace '\W'
            $c = if (-not $d.Pending) { $d.Checks.Where({ $_.Name -eq $Name }, 'First')[0] }
            $Row["c$k"] = $c ? $c.Cell : '-'
            $Row["t$k"] = ($c -and -not $c.NotApplicable) ? $c.Tone : 'muted'
        }
        $Row
    }
    $Blocks.Add((New-CippReportTable -Title 'Domains at a Glance' -Limit 0 -Columns $MatrixColumns -Rows @($MatrixRows)))
    $Blocks.Add((New-CippReportNote -Text 'Pass: in place. Fail: missing or broken. Review: works, with issues to address. Advised: a recommended hardening step that is not yet in place. N/A: managed by Microsoft and cannot be changed. Unknown: could not be checked when the domain was last analysed.'))
    if ($NeedWork.Count) {
        $n = 0
        $Blocks.Add((New-CippReportBullets -Title 'Priority Actions' -Items @(foreach ($g in @($NeedWork.Where({ -not $_.Hardening })) + @($NeedWork.Where({ $_.Hardening }))) {
                        $n++
                        $Actions = @($g.ToFix.Check.Action | Select-Object -Unique)
                        @{ marker = "$n."; label = "$($g.Name) on $(& $DomainWord $g.ToFix.Count):"; text = "$($Actions -join ' ') ($(($g.ToFix.Domain) -join ', '))" }
                    })))
    }

    $Blocks.Add((New-CippReportPage -Title 'Findings by Check' -Subtitle 'Each protection, across every domain'))
    foreach ($g in $Groups) {
        $Blocks.Add((New-CippReportHeading -Title $g.Name))
        $Blocks.Add((New-CippReportParagraph -Text "$($Purpose[$g.Name]) $($Why[$g.Name])"))
        if ($g.ToFix.Count) {
            $Blocks.Add((New-CippReportTable -Limit 0 -Columns @(
                        @{ header = 'Domain'; key = 'domain'; width = 2; bold = $true }
                        @{ header = 'Result'; key = 'label'; width = 1.2; toneField = 'tone' }
                        @{ header = 'What we found'; key = 'found'; width = 4 }
                    ) -Rows @(foreach ($r in $g.ToFix) {
                            @{ domain = $r.Domain; label = $r.Check.Label; tone = $r.Check.Tone; found = $(if ($r.Check.Findings) { ($r.Check.Findings | ForEach-Object { "$($_.TrimEnd('.'))." }) -join ' ' } elseif ($r.Check.Stored) { 'No further detail was recorded.' } else { 'Detailed findings are recorded from the next Domain Analyser run.' }) }
                        })))
            $Advice = @($g.ToFix | Group-Object { $_.Check.Fix } | ForEach-Object { "- **$(($_.Group.Domain) -join ', '):** $($_.Name)" }) -join "`n"
            if ($Data.IncludeDetails) { $Advice = "$Advice`n`n**Target:** $($Target[$g.Name])" }
            $Title = "What we recommend for $($g.Name)"
            if (@($g.ToFix.Where({ $_.Check.Tone -eq 'fail' })).Count) {
                $Blocks.Add((New-CippReportAlertBox -Title $Title -Colour $DangerC -Content $Advice))
            } else {
                $Blocks.Add((New-CippReportInfoBox -Title $Title -Tone warn -Content $Advice))
            }
        }
        $Status = @(
            if ($g.Passing.Count) { "- **Passing:** $($g.Passing -join ', ')" }
            if ($g.Managed.Count) { "- **Managed by Microsoft:** $($g.Managed -join ', ')" }
            if ($g.Unknown.Count) { "- **Not checked:** $($g.Unknown -join ', '). Run the Domain Analyser again to include them." }
        )
        if ($Status) {
            if (-not $g.ToFix.Count -and -not $g.Unknown.Count) {
                $Blocks.Add((New-CippReportClearBox -Title "$($g.Name): no action needed" -Content ($Status -join "`n")))
            } else {
                $Blocks.Add((New-CippReportInfoBox -Title "$($g.Name): other domains" -Content ($Status -join "`n")))
            }
        }
    }
    $Blocks.Add((New-CippReportHeading -Title 'Device Enrolment Records (informational)'))
    $Blocks.Add((New-CippReportParagraph -Text 'These records let Windows devices find Intune enrolment and register with Microsoft Entra ID from a work email address. They only matter if the organisation enrols devices that way, so they do not affect the score.'))
    $Blocks.Add((New-CippReportTable -Limit 0 -Columns @(
                @{ header = 'Domain'; key = 'domain'; width = 2.4; bold = $true }
                @{ header = 'Enterprise Enrollment'; key = 'enrollment'; width = 1.5 }
                @{ header = 'Enterprise Registration'; key = 'registration'; width = 1.5 }
            ) -Rows @(foreach ($d in $Analysed) {
                    @{ domain = $d.Domain; enrollment = ($IntuneLabel[[string]$d.Result.EnterpriseEnrollment] ?? 'Unexpected target'); registration = ($IntuneLabel[[string]$d.Result.EnterpriseRegistration] ?? 'Unexpected target') }
                })))

    if ($Data.IncludeDetails) {
        $Blocks.Add((New-CippReportPage -Title 'Technical Details' -Subtitle 'Published records and individual test results for each domain'))
        foreach ($d in $Analysed) {
            $Result = $d.Result
            $Blocks.Add((New-CippReportHeading -Title "$($d.Domain) ($($d.Score)%)"))
            $Records = @(
                @{ item = 'Analysed'; value = $(if ($d.Analysed) { $d.Analysed.ToString('MMMM d, yyyy', [cultureinfo]'en-US') }) }
                @{ item = 'Name servers'; value = (@($Result.NSRecords) -join ', ') }
                @{ item = 'Mail provider'; value = [string]$Result.MailProvider }
                @{ item = 'MX records'; value = (@($Result.ActualMXRecords | ForEach-Object { "$($_.Priority) $($_.Hostname)" }) -join ', ') }
                @{ item = 'SPF record'; value = [string]$Result.ActualSPFRecord }
                @{ item = 'Expected SPF include'; value = [string]$Result.ExpectedSPFRecord }
                @{ item = 'DMARC record'; value = [string]$Result.DMARCFullPolicy }
                @{ item = 'DKIM selectors checked'; value = $d.Selectors }
                @{ item = 'DKIM keys found'; value = (@($Result.DKIMRecords | Where-Object { $_.Record } | ForEach-Object { $_.Selector }) -join ', ') }
                @{ item = 'MTA-STS'; value = [string]$Result.MTASTS }
                @{ item = 'Enterprise Enrollment'; value = [string]$Result.EnterpriseEnrollment }
                @{ item = 'Enterprise Registration'; value = [string]$Result.EnterpriseRegistration }
            )
            foreach ($r in $Records) { if ([string]::IsNullOrWhiteSpace($r.value)) { $r.value = 'None found' } }
            $Blocks.Add((New-CippReportTable -Limit 0 -Columns @(
                        @{ header = 'Record'; key = 'item'; width = 1.6; bold = $true }
                        @{ header = 'Value'; key = 'value'; width = 5 }
                    ) -Rows $Records))
            $Tests = foreach ($c in $d.Checks.Where({ -not $_.NotApplicable })) {
                foreach ($m in $c.Stored.Fails) { if ($m) { @{ check = $c.Name; result = $c.Hardening ? 'Warn' : 'Fail'; tone = $c.Hardening ? 'warn' : 'fail'; message = $m } } }
                foreach ($m in $c.Stored.Warns) { if ($m) { @{ check = $c.Name; result = 'Warn'; tone = 'warn'; message = $m } } }
                foreach ($m in $c.Stored.Passes) { if ($m) { @{ check = $c.Name; result = 'Pass'; tone = 'pass'; message = $m } } }
            }
            $Blocks.Add((New-CippReportTable -Limit 0 -EmptyText 'Individual test results are recorded from the next Domain Analyser run.' -Columns @(
                        @{ header = 'Check'; key = 'check'; width = 1 }
                        @{ header = 'Result'; key = 'result'; width = 0.7; toneField = 'tone' }
                        @{ header = 'Detail'; key = 'message'; width = 5 }
                    ) -Rows @($Tests)))
        }
    }
    $Blocks.Add((New-CippReportNote -Text "This report is a point-in-time assessment of the organisation's public DNS records as recorded by the Domain Analyser on $DateText. DNS changes can take effect at any time, and the report does not examine mail servers, mailboxes or account security. Results should be confirmed before changes are made."))

    @{
        Blocks    = @($Blocks)
        Variables = @{
            coverlabel         = 'Domain Security Assessment'
            coversubtitle      = 'Email security and DNS health across every domain.'
            coverfooternote    = 'Point-in-time assessment of public DNS records'
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "$TenantName $([char]0x2014) Domain Security"
        }
    }
}
