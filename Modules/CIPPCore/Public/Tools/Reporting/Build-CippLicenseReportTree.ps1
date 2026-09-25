function Build-CippLicenseReportTree {
    <#
    .SYNOPSIS
        Compose the License Optimisation report as a component tree (server port of the client
        LicenseReportButton.jsx LicenseReportDocument).
    .PARAMETER Data
        TenantName plus the Get-CIPPLicenseRecommendation result fields (Summary, Optimization,
        Downgrades, Upgrades, Terms, Products, Capabilities). Hashtables (a sample read with
        ConvertFrom-Json -AsHashtable) and PSCustomObjects (a live report) both work.
    .PARAMETER Sections
        Optional section switches: spend, reclaim, downgrades, upgrades, terms, method. Only an explicit
        $false drops a section; the summary page is always included.
    .PARAMETER GeneratedOn
        The generation date quoted on the method page (the cover date is ConvertTo-CippReportPdf's).
        Defaults to today in the instance's timezone (CIPP_TIMEZONE), as the cover's does.
        Returns @{ Blocks; Variables }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [hashtable]$Sections = @{},
        [string]$GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $(try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc })).ToString('MMMM d, yyyy', [cultureinfo]'en-US')
    )

    # This file stays ASCII: the typographic characters the client prints are built here.
    $MiddleDot = [string][char]0x00B7
    $EmDash = [string][char]0x2014
    $Ellipsis = [string][char]0x2026
    $OpenQuote = [string][char]0x201C
    $CloseQuote = [string][char]0x201D
    # Heavy check mark + VS16: the kit draws it as the same Twemoji image the client shows.
    $Check = [string][char]0x2714 + [string][char]0xFE0F
    $Colours = @{ danger = '#742A2A'; warning = '#744210'; success = '#22543D' }
    $Invariant = [cultureinfo]::InvariantCulture

    # Number(v ?? 0) and toLocaleString() (en-US) from the client.
    function nz($v) { if ($null -eq $v) { 0 } else { [double]$v } }
    function num($v) { ([decimal](nz $v)).ToString('#,0.###', $Invariant) }
    # JS Math.round: half rounds up, where [math]::Round rounds half to even.
    function jsRound([double]$x) { [math]::Floor($x + 0.5) }
    # `nz(v) || fallback`.
    function orDefault($v, $Fallback) { if ((nz $v) -ne 0) { nz $v } else { $Fallback } }

    $Summary = $Data.Summary ?? @{}
    # `?? @()` so a missing list is empty rather than @($null), which would render as one blank row.
    $Products = @($Data.Products ?? @())
    $Opportunities = @($Data.Optimization.Opportunities ?? @())
    $Downgrades = @($Data.Downgrades ?? @())
    $Upgrades = @($Data.Upgrades ?? @())
    $Terms = @($Data.Terms ?? @())
    $Capabilities = @($Data.Capabilities ?? @())
    $TenantName = [string]$Data.TenantName
    $TenantHtml = [System.Net.WebUtility]::HtmlEncode($TenantName)
    $Show = @{}
    foreach ($Key in 'spend', 'reclaim', 'downgrades', 'upgrades', 'terms', 'method') { $Show[$Key] = $Sections[$Key] -ne $false }

    # Money as the client's Intl.NumberFormat('en-US', { style: 'currency' }) prints it: whole units for
    # the big figures, cents for a per-seat price, half away from zero on the decimal value (formatting a
    # double would round 58.5 to 58 where Intl gives 59). An unusable code falls back to USD as the
    # client's try/catch does.
    $Currency = ([string]$Summary.Currency).ToUpperInvariant()
    if ($Currency -notmatch '^[A-Z]{3}$') { $Currency = 'USD' }
    # ponytail: symbols for the catalog currencies the PDF fonts can draw; any other code prints as
    # "CODE 1,234" like Intl does for CHF/SEK. Glyphs such as INR/KRW's are not in the fonts, so they
    # stay as codes rather than turning into '?'. Intl joins code and number with a no-break space; a plain
    # one is kept here so a narrow table cell wraps between the two instead of inside the number
    # ("KRW 19,237." / "50").
    $Symbol = switch ($Currency) {
        'USD' { '$' } 'EUR' { [string][char]0x20AC } 'GBP' { [string][char]0x00A3 } 'JPY' { [string][char]0x00A5 }
        'CAD' { 'CA$' } 'AUD' { 'A$' } 'NZD' { 'NZ$' } 'CNY' { 'CN' + [char]0x00A5 } 'HKD' { 'HK$' }
        'MXN' { 'MX$' } 'BRL' { 'R$' } 'TWD' { 'NT$' }
        default { $Currency + ' ' }
    }
    function money($v, [int]$Digits) {
        $x = [math]::Round([decimal](nz $v), $Digits, [MidpointRounding]::AwayFromZero)
        $Sign = if ($x -lt 0) { '-' } else { '' }
        $Sign + $Symbol + [math]::Abs($x).ToString("N$Digits", $Invariant)
    }
    function whole($v) { money $v 0 }
    function cents($v) { money $v 2 }

    $ReportDays = orDefault $Summary.ReportPeriodDays 180
    $InactiveDays = orDefault $Summary.InactiveDays 90
    $TenureMonths = orDefault $Summary.TenureMonths 6
    $UpliftPct = jsRound ((orDefault $Summary.MonthlyCommitmentUplift 0.2) * 100)
    $MonthlySpend = nz $Summary.MonthlySpend
    $PotentialMonthly = nz $Summary.TotalPotentialMonthly
    $PotentialAnnual = nz $Summary.TotalPotentialAnnual
    # The client tests `=== false`, so a missing setting counts as protected.
    $ProtectOff = ($Summary.ProtectSecurityFeatures -is [bool]) -and -not $Summary.ProtectSecurityFeatures

    # Grade the licensing from the share of monthly spend the report could recover.
    $Share = 0
    if ($MonthlySpend -le 0) { $Level = 'No priced spend'; $Severity = 'low' }
    else {
        $Share = jsRound ($PotentialMonthly / $MonthlySpend * 100)
        if ($Share -ge 15) { $Level = 'Significant savings available'; $Severity = 'high' }
        elseif ($Share -ge 5) { $Level = 'Some savings available'; $Severity = 'medium' }
        else { $Level = 'Well matched'; $Severity = 'low' }
    }
    $SeverityColour = @{ high = $Colours.danger; medium = $Colours.warning }[$Severity] ?? $Colours.success

    $Blocks = [System.Collections.Generic.List[object]]::new()

    # -- Summary (always included) --
    $Blocks.Add((New-CippReportPage -Title 'Summary' -Subtitle 'The numbers that matter'))
    $Blocks.Add((New-CippReportParagraph -Html ('<p>Microsoft 365 is bought per person, per plan, per month. Every plan bundles a set of services, and each person is meant to hold the plan that matches what they do. Over time that drifts: people leave, roles change, and plans bought for one reason keep renewing. This report compares what <b>{0}</b> pays for with what its people actually used over the last {1} days.</p>' -f $TenantHtml, $ReportDays)))
    $Blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (whole $MonthlySpend); label = 'Spend per month' }
                @{ value = (whole $PotentialMonthly); label = 'Could be saved per month'; colour = $(if ($PotentialMonthly -gt 0) { $Colours.success }) }
                @{ value = (whole $PotentialAnnual); label = 'Could be saved per year'; colour = $(if ($PotentialAnnual -gt 0) { $Colours.success }) }
                @{ value = (num $Summary.ReclaimableSeats); label = 'Licenses nobody uses'; colour = $(if ((nz $Summary.ReclaimableSeats) -gt 0) { $Colours.warning }) }
            )))
    $Assessment = switch ($Severity) {
        'high' { "About $Share% of the monthly licensing bill could be recovered. That is well past what normal staff turnover explains, and it means plans are being paid for out of habit rather than need. The actions in this report are worth scheduling now." }
        'medium' { "About $Share% of the monthly licensing bill could be recovered. Licensing is broadly right; the savings are in a handful of licenses and plans that no longer match how people work." }
        default {
            if ($MonthlySpend -gt 0) { 'What is paid for closely matches what is used. Nothing here needs action beyond repeating this review as people join and leave.' }
            else { 'No list price is known for the plans in this tenant, so no spend or savings could be calculated. Prices can be added on the License Pricing page.' }
        }
    }
    $Blocks.Add((New-CippReportAlertBox -Title "Licensing: $Level" -Colour $SeverityColour -Content $Assessment))

    $Sources = @(
        if ((nz $Summary.ReclaimableMonthly) -gt 0) {
            @{ label = '{0} a month by removing licenses nobody uses.' -f (whole $Summary.ReclaimableMonthly); text = '{0} licenses are paid for but sit with nobody, with switched-off accounts, or with people who have not signed in for {1} days.' -f (num $Summary.ReclaimableSeats), $InactiveDays }
        }
        if ((nz $Summary.DowngradeMonthly) -gt 0) {
            @{ label = '{0} a month by moving people to a cheaper plan.' -f (whole $Summary.DowngradeMonthly); text = '{0} people hold a plan that includes services they have not used in the last {1} days.' -f (num $Summary.DowngradeSeats), $ReportDays }
        }
        if ((nz $Summary.ConsolidationMonthly) -gt 0) {
            @{ label = '{0} a month by combining separate plans into one bundle.' -f (whole $Summary.ConsolidationMonthly); text = 'Some people hold two or more plans that together cost more than a single bundle with the same features.' }
        }
        if ((nz $Summary.TermMonthly) -gt 0) {
            @{ label = '{0} a month by paying yearly for stable seats.' -f (whole $Summary.TermMonthly); text = 'Month-to-month licenses cost {0}% more than a yearly commitment. Seats that have been with the same person for {1} months or longer are safe to commit to.' -f $UpliftPct, $TenureMonths }
        }
    )
    if ($Sources.Count -gt 0) { $Blocks.Add((New-CippReportBullets -Title 'Where the savings come from' -Items $Sources)) }

    $Blocks.Add((New-CippReportHeading -Title 'How to read this report'))
    $Blocks.Add((New-CippReportInfoBox -Title 'What was measured' -Content 'Microsoft records, per person, the last day each service was used: email, Teams, files, the installed Office apps, and Copilot. Those dates were compared with what each plan includes. A recommendation is only made where that evidence exists.'))
    $NotMeasured = if ($ProtectOff) { 'This report was configured to treat them as optional, so a cheaper plan may drop them; each such case lists exactly what would be lost.' }
    else { 'This report keeps every one of them: nobody is moved to a plan that removes a security feature they hold today.' }
    $Blocks.Add((New-CippReportInfoBox -Title 'What was not measured' -Content "Security and management features such as device management, sign-in protection and threat protection have no per-person usage record. $NotMeasured"))

    # -- What you pay for --
    if ($Show.spend) {
        $Blocks.Add((New-CippReportPage -Title 'What you pay for' -Subtitle 'Every plan, seats owned versus in use'))
        $Blocks.Add((New-CippReportParagraph -Html '<p>Each row is one plan. <b>Owned</b> is how many seats are bought; <b>in use</b> is how many are given to a person; the difference is paid for and unused. Prices are Microsoft public list prices unless a price has been set specifically for this organisation.</p>'))
        # The six largest priced plans, then everything else as one slice.
        $Priced = @($Products | Where-Object { (nz $_.MonthlySpend) -gt 0 })
        $SpendSeries = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in ($Priced | Select-Object -First 6)) { $SpendSeries.Add(@{ label = [string]$Row.License; value = (nz $Row.MonthlySpend) }) }
        $Rest = ($Priced | Select-Object -Skip 6 | ForEach-Object { nz $_.MonthlySpend } | Measure-Object -Sum).Sum
        if ($Rest -gt 0) { $SpendSeries.Add(@{ label = 'Other plans'; value = $Rest }) }
        if ($SpendSeries.Count -gt 0) { $Blocks.Add((New-CippReportChart -Kind donut -Title 'Monthly spend by plan' -CentreLabel 'per month' -Data @($SpendSeries))) }
        $SpendRows = foreach ($Row in $Products) {
            @{
                plan         = [string]$Row.License
                owned        = (num $Row.TotalSeats)
                used         = (num $Row.AssignedSeats)
                unused       = (num $Row.UnusedSeats)
                unusedColour = $(if ((nz $Row.UnusedSeats) -gt 0) { $Colours.warning })
                unit         = $(if ($Row.PriceKnown) { cents $Row.UnitCost } else { $EmDash })
                monthly      = $(if ($Row.PriceKnown) { whole $Row.MonthlySpend } else { 'not priced' })
            }
        }
        $Blocks.Add((New-CippReportTable -Limit 30 -Rows @($SpendRows) -EmptyText 'No licenses were found for this organisation.' -Columns @(
                    @{ header = 'Plan'; key = 'plan'; width = 3; bold = $true }
                    @{ header = 'Owned'; key = 'owned'; width = 0.8; align = 'right' }
                    @{ header = 'In use'; key = 'used'; width = 0.8; align = 'right' }
                    @{ header = 'Unused'; key = 'unused'; width = 0.8; align = 'right'; colourField = 'unusedColour' }
                    @{ header = 'Per seat'; key = 'unit'; width = 1; align = 'right' }
                    @{ header = 'Per month'; key = 'monthly'; width = 1.1; align = 'right' }
                )))
    }

    # -- Licenses you can remove --
    if ($Show.reclaim) {
        $TierText = @{
            UnassignedSeats = 'Paid for but not given to anyone'
            DisabledAccount = 'Given to an account that has been switched off'
            Inactive        = 'Given to someone who has not signed in for a long time'
            Overlap         = 'Duplicate: another plan already includes it'
        }
        $Blocks.Add((New-CippReportPage -Title 'Licenses you can remove' -Subtitle 'Paid for, used by nobody'))
        $Blocks.Add((New-CippReportParagraph -Text 'These licenses cost money every month and do no work. Removing them changes nothing for anyone who is actually working. Seats bought on a yearly term cannot be reduced until the term renews, but can be reassigned to new starters instead of buying more.'))
        # The mailbox-only review tier claims no saving and is superseded by the downgrade pass, so it
        # stays on the admin page. -Stable keeps equal savings in server order, as the client's sort does.
        $ReclaimRows = @($Opportunities | Where-Object { $_.Tier -ne 'Downgrade' } | ForEach-Object {
                @{
                    plan        = [string]$_.License
                    finding     = $(if ($TierText.ContainsKey([string]$_.Tier)) { $TierText[[string]$_.Tier] } else { [string]$_.FindingLabel })
                    seats       = (num $_.Seats)
                    saving      = $(if ($_.PriceKnown) { whole $_.MonthlySaving } else { 'not priced' })
                    savingValue = (nz $_.MonthlySaving)
                }
            } | Sort-Object -Property @{ Expression = { $_.savingValue }; Descending = $true } -Stable)
        if ($ReclaimRows.Count -gt 0) {
            $Blocks.Add((New-CippReportTable -Limit 30 -Rows $ReclaimRows -Columns @(
                        @{ header = 'Plan'; key = 'plan'; width = 2.2; bold = $true }
                        @{ header = 'Why it can go'; key = 'finding'; width = 3 }
                        @{ header = 'Seats'; key = 'seats'; width = 0.7; align = 'right' }
                        @{ header = 'Saving per month'; key = 'saving'; width = 1.3; align = 'right' }
                    )))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title "$Check Nothing to remove" -Content 'Every license is assigned to an active person. Turnover is being handled well.'))
        }
    }

    # -- Cheaper plans --
    if ($Show.downgrades) {
        $Blocks.Add((New-CippReportPage -Title 'Cheaper plans' -Subtitle 'People whose plan includes more than they use'))
        $Blocks.Add((New-CippReportParagraph -Text ('Each line groups people on the same plan who used the same subset of it. The suggested plan is the cheapest one that still includes everything they used in the last {0} days. What they would lose is listed so the decision is an informed one; a person who needs one of those services in the coming months should stay where they are.' -f $ReportDays)))
        if ([bool]$Summary.AnonymizedReports) {
            $Blocks.Add((New-CippReportAlertBox -Title 'Usage reports are anonymised' -Colour $Colours.warning -Content "Microsoft is configured to hide names in this organisation's usage reports, so activity could not be matched to people and no plan changes are suggested. The setting can be switched off in the Microsoft 365 admin centre."))
        } elseif ($Downgrades.Count -gt 0) {
            $DowngradeRows = foreach ($Row in $Downgrades) {
                @{
                    from   = [string]$Row.FromLicense
                    to     = $(if ($Row.Action -eq 'Remove') { 'Remove the plan' } else { [string]$Row.ToLicense })
                    seats  = (num $Row.Seats)
                    unit   = (cents $Row.UnitSaving)
                    saving = (whole $Row.MonthlySaving)
                }
            }
            $Blocks.Add((New-CippReportTable -Limit 20 -Rows @($DowngradeRows) -Columns @(
                        @{ header = 'Current plan'; key = 'from'; width = 2; bold = $true }
                        @{ header = 'Suggested'; key = 'to'; width = 2 }
                        @{ header = 'People'; key = 'seats'; width = 0.7; align = 'right' }
                        @{ header = 'Each'; key = 'unit'; width = 1; align = 'right' }
                        @{ header = 'Saving per month'; key = 'saving'; width = 1.3; align = 'right' }
                    )))
            # The client's arrow (U+2192) is not in the PDF fonts, so the label uses '->'.
            $DowngradeItems = foreach ($Row in ($Downgrades | Select-Object -First 8)) {
                $Keeps = @($Row.Keeps ?? @())
                $Loses = @($Row.Loses ?? @())
                $Target = if ($Row.Action -eq 'Remove') { 'no plan' } else { [string]$Row.ToLicense }
                $KeepText = if ($Keeps.Count -gt 0) { 'keeps {0}. ' -f ($Keeps -join ', ') } else { '' }
                $LoseText = if ($Loses.Count -gt 0) { 'Loses {0}.' -f ($Loses -join ', ') } else { 'Loses nothing that was used.' }
                @{ label = '{0} -> {1}:' -f $Row.FromLicense, $Target; text = $KeepText + $LoseText }
            }
            $Blocks.Add((New-CippReportBullets -Items @($DowngradeItems)))
            if ($Downgrades.Count -gt 8) {
                $Blocks.Add((New-CippReportNote -Text ('{0} and {1} more groups, listed in full on the admin page.' -f $Ellipsis, ($Downgrades.Count - 8))))
            }
        } else {
            $Blocks.Add((New-CippReportClearBox -Title "$Check Plans match usage" -Content 'Nobody holds a plan whose measured services they left unused. No cheaper plan is suggested.'))
        }
    }

    # -- Better plans --
    if ($Show.upgrades) {
        $Blocks.Add((New-CippReportPage -Title 'Better plans' -Subtitle 'Where a different plan pays off'))
        $Blocks.Add((New-CippReportParagraph -Title 'Combine separate plans' -Text 'Some people hold two or more plans bought at different times. When one bundle includes the same features for less, the bundle is the better buy.'))
        $Consolidations = @($Upgrades | Where-Object { $_.Type -eq 'Consolidate' })
        if ($Consolidations.Count -gt 0) {
            $ConsolidationRows = foreach ($Row in $Consolidations) {
                @{
                    from   = (@($Row.FromLicenses ?? @()) -join ' + ')
                    to     = [string]$Row.ToLicense
                    seats  = (num $Row.Seats)
                    now    = (cents $Row.UnitCost)
                    bundle = (cents $Row.TargetCost)
                    saving = (whole (-1 * (nz $Row.MonthlyDelta)))
                }
            }
            $Blocks.Add((New-CippReportTable -Limit 15 -Rows @($ConsolidationRows) -Columns @(
                        @{ header = 'Current plans'; key = 'from'; width = 2.6; bold = $true }
                        @{ header = 'Suggested bundle'; key = 'to'; width = 2 }
                        @{ header = 'People'; key = 'seats'; width = 0.7; align = 'right' }
                        @{ header = 'Now'; key = 'now'; width = 0.9; align = 'right' }
                        @{ header = 'Bundle'; key = 'bundle'; width = 0.9; align = 'right' }
                        @{ header = 'Saving per month'; key = 'saving'; width = 1.3; align = 'right' }
                    )))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title "$Check No cheaper bundles" -Content "Nobody's combination of plans costs more than a single bundle would."))
        }

        $Blocks.Add((New-CippReportParagraph -Title 'People with no security protection' -Text 'These people hold plans that include no device management, no advanced sign-in protection and no device threat protection. That is a business risk rather than a saving, so the figure below is an added cost. It is the cheapest plan that gives them all three.'))
        $Protections = @($Upgrades | Where-Object { $_.Type -eq 'Protect' })
        if ($Protections.Count -gt 0) {
            $ProtectionRows = foreach ($Row in $Protections) {
                @{
                    from  = (@($Row.FromLicenses ?? @()) -join ' + ')
                    to    = [string]$Row.ToLicense
                    seats = (num $Row.Seats)
                    unit  = (cents $Row.UnitDelta)
                    delta = (whole $Row.MonthlyDelta)
                }
            }
            $Blocks.Add((New-CippReportTable -Limit 15 -Rows @($ProtectionRows) -Columns @(
                        @{ header = 'Current plans'; key = 'from'; width = 2.4; bold = $true }
                        @{ header = 'Suggested'; key = 'to'; width = 2 }
                        @{ header = 'People'; key = 'seats'; width = 0.7; align = 'right' }
                        @{ header = 'Extra per person'; key = 'unit'; width = 1.2; align = 'right' }
                        @{ header = 'Extra per month'; key = 'delta'; width = 1.3; align = 'right' }
                    )))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title "$Check Everyone is covered" -Content 'Every licensed person holds a plan with device management, sign-in protection and device threat protection.'))
        }
    }

    # -- Yearly or monthly --
    if ($Show.terms) {
        $Blocks.Add((New-CippReportPage -Title 'Yearly or monthly' -Subtitle 'Committing to the seats that will stay'))
        $Blocks.Add((New-CippReportParagraph -Html ('<p>Microsoft sells the same plan two ways. A <b>yearly</b> commitment is cheaper but cannot be reduced until it renews. A <b>monthly</b> commitment costs about {0}% more but can be dropped at any time. The right mix is to commit yearly to the seats that will still be there in a year and keep the rest monthly. A seat that has been with the same person for {1} months or more is treated as one that will stay.</p>' -f $UpliftPct, $TenureMonths)))
        if ($Terms.Count -gt 0) {
            $TermRows = foreach ($Row in $Terms) {
                @{
                    plan      = [string]$Row.License
                    used      = (num $Row.AssignedSeats)
                    stable    = (num $Row.StableSeats)
                    yearlyNow = $(if ($Row.TermKnown) { num $Row.YearlySeats } else { 'unknown' })
                    yearly    = (num $Row.RecommendedAnnual)
                    monthly   = (num $Row.RecommendedMonthly)
                    saving    = $(if ($Row.TermKnown -and $Row.PriceKnown) { whole $Row.MonthlySaving } else { $EmDash })
                }
            }
            $Blocks.Add((New-CippReportTable -Limit 30 -Rows @($TermRows) -Columns @(
                        @{ header = 'Plan'; key = 'plan'; width = 2.4; bold = $true }
                        @{ header = 'In use'; key = 'used'; width = 0.7; align = 'right' }
                        @{ header = "Held $TenureMonths+ mo"; key = 'stable'; width = 0.9; align = 'right' }
                        @{ header = 'Yearly now'; key = 'yearlyNow'; width = 0.9; align = 'right' }
                        @{ header = 'Suggested yearly'; key = 'yearly'; width = 1.1; align = 'right' }
                        @{ header = 'Suggested monthly'; key = 'monthly'; width = 1.1; align = 'right' }
                        @{ header = 'Saving per month'; key = 'saving'; width = 1.2; align = 'right' }
                    )))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title 'No plans to assess' -Content 'No assigned plans were found.'))
        }
        $Locked = @(foreach ($Row in $Terms) {
                $Seats = nz $Row.LockedUnusedSeats
                if ($Seats -le 0) { continue }
                $Renewal = if ($null -ne $Row.NextRenewalDays) { ', renews in {0} days' -f (num $Row.NextRenewalDays) } else { '' }
                '{0}: {1} yearly seat{2} unassigned{3}' -f $Row.License, (num $Seats), $(if ($Seats -eq 1) { '' } else { 's' }), $Renewal
            })
        if ($Locked.Count -gt 0) {
            $Blocks.Add((New-CippReportInfoBox -Title 'Yearly seats that nobody holds' -Content (($Locked -join '. ') + '. These are paid for until renewal; reduce the count before that date.')))
        }
        if (@($Terms | Where-Object { -not $_.TermKnown }).Count -gt 0) {
            $Blocks.Add((New-CippReportNote -Text ('{0}Unknown{1} means Microsoft did not report the commitment term for that plan, so the current yearly/monthly split could not be read and no saving is claimed.' -f $OpenQuote, $CloseQuote)))
        }
    }

    # -- How this was measured --
    if ($Show.method) {
        $Measured = @($Capabilities | Where-Object { $_.measurable } | ForEach-Object { [string]$_.label }) -join ', '
        $Unmeasured = @($Capabilities | Where-Object { -not $_.measurable } | ForEach-Object { [string]$_.label }) -join ', '
        $PriceCurrency = if ($Summary.Currency) { [string]$Summary.Currency } else { 'USD' }
        $Blocks.Add((New-CippReportPage -Title 'How this was measured' -Subtitle 'Sources, window and assumptions'))
        $Blocks.Add((New-CippReportBullets -Items @(
                    @{ label = 'Prices.'; text = "Microsoft public list prices per user per month on a yearly commitment, in $PriceCurrency, unless a specific price was entered for this organisation. Real invoices may differ from list price." }
                    @{ label = 'Usage window.'; text = "The last $ReportDays days of Microsoft usage reports for email, Teams, OneDrive and SharePoint, the installed Office apps, and Copilot. A person counts as inactive after $InactiveDays days without a sign-in." }
                    @{ label = 'Measured services.'; text = $Measured }
                    @{ label = 'Services with no usage record.'; text = "$Unmeasured. $(if ($ProtectOff) { 'Treated as optional in this report.' } else { 'Always kept in this report.' })" }
                    @{ label = 'Plan comparison.'; text = 'Plans are compared by the services Microsoft lists for each one. Business plans are only suggested where the organisation is within their 300-user limit; frontline plans only to people already on one.' }
                    @{ label = 'Yearly versus monthly.'; text = "Microsoft records when each person's license was last changed. A seat unchanged for $TenureMonths months or more is treated as stable. The saving is the $UpliftPct% premium on monthly-commitment seats that could move to a yearly term." }
                    @{ label = 'Report generated.'; text = "$GeneratedOn, from data collected by the management platform." }
                )))
    }

    $Separator = " $MiddleDot "
    @{
        Blocks    = @($Blocks)
        Variables = @{
            coverlabel         = 'Microsoft 365 Licensing Review'
            covertitle         = 'Licensing'
            coveraccent        = 'Report'
            coversubtitle      = "What $TenantName pays Microsoft for each month, which of it is used, and where the same work could be done for less."
            covermeta          = '{0} people licensed{1}{2} plans{1}{3} per month' -f (num $Summary.LicensedUsers), $Separator, (num $Products.Count), (whole $MonthlySpend)
            covermetanote      = $(if ($PotentialAnnual -gt 0) { 'Potential saving: {0} per year' -f (whole $PotentialAnnual) } else { 'No savings identified' })
            coverfooternote    = "Confidential $EmDash Prepared for the leadership team"
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "$TenantName $EmDash Licensing"
        }
    }
}
