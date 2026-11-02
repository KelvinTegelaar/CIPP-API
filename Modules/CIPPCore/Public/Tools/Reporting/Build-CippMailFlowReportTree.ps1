function Build-CippMailFlowReportTree {
    <#
    .SYNOPSIS
        Compose the Exchange Mail Flow report as a component tree (server port of MailFlowReportButton.jsx).
    .PARAMETER Data
        Mail flow data: days, totals, directionTotals, daily[], topSenders[], topSpamRecipients[].
        Returns @{ Blocks; Variables }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    function nz($v) { if ($null -eq $v) { 0 } else { [double]$v } }
    function num($v) { '{0:N0}' -f (nz $v) }
    function pct($part, $whole) { if ($whole -gt 0) { [math]::Round(($part / $whole) * 1000) / 10 } else { 0 } }
    $dispositions = @(
        @{ key = 'GoodMail'; label = 'Good mail' }, @{ key = 'TransportRules'; label = 'Transport rules' }
        @{ key = 'SpamDetections'; label = 'Spam' }, @{ key = 'EdgeBlockSpam'; label = 'Edge blocked spam' }
        @{ key = 'EmailPhish'; label = 'Phish' }, @{ key = 'EmailMalware'; label = 'Malware' }
    )
    $days = if ((nz $Data.days) -gt 0) { [int]$Data.days } else { 14 }
    $totals = if ($Data.totals) { $Data.totals } else { @{} }
    $dir = if ($Data.directionTotals) { $Data.directionTotals } else { @{} }
    # `?? @()` so a missing list is empty rather than @($null), which would render as one blank row.
    $daily = @($Data.daily ?? @())
    $topSenders = @($Data.topSenders ?? @())
    $topSpam = @($Data.topSpamRecipients ?? @())

    $totalMail = ($dispositions | ForEach-Object { nz $totals[$_.key] } | Measure-Object -Sum).Sum
    $goodPct = pct (nz $totals.GoodMail) $totalMail
    $phish = nz $totals.EmailPhish; $malware = nz $totals.EmailMalware; $threats = $phish + $malware
    $transportRules = nz $totals.TransportRules
    $targeted = pct $threats $totalMail
    $spam = pct ((nz $totals.SpamDetections) + (nz $totals.EdgeBlockSpam)) $totalMail
    $hygiene = if ($totalMail -le 0) { 'Good' }
    elseif ($targeted -gt 1 -or $spam -gt 25) { 'Attention Needed' }
    elseif ($targeted -gt 0.25 -or $spam -gt 10) { 'Fair' }
    else { 'Good' }
    $dangerC = '#742A2A'; $warnC = '#744210'
    $sevColour = @{ 'Attention Needed' = $dangerC; Fair = $warnC; Good = '#22543D' }[$hygiene]

    $dayLabel = { param($v) if ($v) { ([datetime]$v).ToString('MMM d') } else { '' } }
    $volumeSeries = foreach ($row in $daily) { @{ label = (& $dayLabel $row.date); value = ($dispositions | ForEach-Object { nz $row[$_.key] } | Measure-Object -Sum).Sum } }
    $directionSeries = @(
        @{ label = 'Inbound'; value = (nz $dir.Inbound) }
        @{ label = 'Outbound'; value = (nz $dir.Outbound) }
        @{ label = 'Intra-org'; value = (nz $dir.IntraOrg) }
    )
    $dispositionRows = foreach ($d in $dispositions) { @{ disposition = $d.label; messages = (num $totals[$d.key]); share = "$(pct (nz $totals[$d.key]) $totalMail)%" } }

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle "Email traffic over the last $days days"))
    $blocks.Add((New-CippReportParagraph -Html ('<p>Every message entering or leaving the organisation is given a disposition - delivered, held by a transport rule, filtered as spam, or blocked as phishing or malware. Those dispositions are the clearest single measure of what the mail environment is being asked to handle, because they count what the filters actually did rather than what they are configured to do. This report covers the last {0} days of mail flow at <b>{1}</b>.</p>' -f $days, [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName))))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (num $totalMail); label = 'Total Messages' }
                @{ value = "$goodPct%"; label = 'Delivered Clean' }
                @{ value = (num $phish); label = 'Phish Blocked'; colour = $(if ($phish -gt 0) { $warnC }) }
                @{ value = (num $malware); label = 'Malware Blocked'; colour = $(if ($malware -gt 0) { $dangerC }) }
            )))
    $hygText = switch ($hygiene) {
        'Attention Needed' { 'Threat traffic is a material share of total mail. At this rate the organisation is being targeted rather than incidentally caught by bulk campaigns, and the filters are absorbing volume that protection policy and user awareness should be reducing at source. Treat the recommendations as current work.' }
        'Fair' { 'Threats are being caught at a level that is normal for an organisation of this profile, but not negligible. The filtering is working; the value now is in checking which users absorb most of it and whether their protection matches their exposure.' }
        default { 'Threat traffic is a small fraction of total mail and is being stopped before delivery. Nothing here needs action beyond keeping the review cadence, since a change in this profile is usually the first visible sign of a campaign starting.' }
    }
    $blocks.Add((New-CippReportAlertBox -Title "Mail Hygiene: $hygiene" -Colour $sevColour -Content $hygText))
    $blocks.Add((New-CippReportInfoBox -Title 'What this data is' -Content "Figures come from Microsoft's mail flow status report for the tenant, aggregated as daily counts per disposition and direction. It is a count of messages, not a record of them: individual senders, subjects and recipients are not part of this data set, and a message appears once under the disposition that was applied to it."))
    $blocks.Add((New-CippReportInfoBox -Title 'What it does not show' -Content 'A blocked message is a filter working, not an incident. Nothing here indicates that a threat reached a user or that an account was compromised - that requires message trace and sign-in data, which are reviewed separately. Equally, a clean result does not prove nothing got through; it proves nothing was recognised.'))

    # -- Volume & Dispositions --
    $blocks.Add((New-CippReportPage -Title 'Volume & Dispositions' -Subtitle 'How much mail, and what happened to it'))
    $blocks.Add((New-CippReportHeading -Title 'Daily Volume'))
    $blocks.Add((New-CippReportParagraph -Text 'Total messages handled per day across every disposition. Steady volume with occasional peaks is normal; a sustained step change usually reflects a business event - a campaign, an onboarding, a new integration - and is worth being able to explain.'))
    $blocks.Add((New-CippReportChart -Kind trend -Title 'Messages per day' -Caption ("{0} messages over {1} days" -f (num $totalMail), $days) -Data @($volumeSeries)))
    $blocks.Add((New-CippReportHeading -Title 'Dispositions'))
    $blocks.Add((New-CippReportParagraph -Text 'The share each disposition accounts for matters more than the counts. Good mail should dominate; anything else growing as a proportion is the signal.'))
    $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Disposition'; key = 'disposition'; width = 2.4 }, @{ header = 'Messages'; key = 'messages'; width = 1.2 }, @{ header = '% of Total'; key = 'share'; width = 1 }) -Rows @($dispositionRows)))
    $blocks.Add((New-CippReportHeading -Title 'Direction'))
    $blocks.Add((New-CippReportParagraph -Text 'Inbound, outbound and internal traffic in proportion. An unusual outbound share is the one to watch: mail leaving in volume that the business did not generate is how a compromised mailbox or an unsecured relay first shows up in these figures.'))
    $blocks.Add((New-CippReportChart -Kind donut -Title 'Messages by direction' -CentreLabel 'messages' -Data @($directionSeries)))

    # -- Senders & Spam Targets --
    $blocks.Add((New-CippReportPage -Title 'Senders & Spam Targets' -Subtitle 'Who sends the most, and who is targeted'))
    $blocks.Add((New-CippReportHeading -Title 'Top Mail Senders'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'The heaviest senders are normally the ones you would expect - shared mailboxes, ticketing systems, scan-to-email devices, marketing platforms. What is worth a second look is a name that does not belong on that list. A user account sending at machine volume is either an unmanaged automation nobody documented, or a mailbox someone else is using.'))
    if ($topSenders.Count -gt 0) {
        $blocks.Add((New-CippReportTable -Limit 10 -Columns @(@{ header = 'Sender'; key = 'name'; width = 3 }, @{ header = 'Messages'; key = 'count'; width = 1 }) -Rows @($topSenders | ForEach-Object { @{ name = ($_.Name ?? $_.name ?? 'Unknown'); count = (num ($_.Count ?? $_.count)) } })))
    } else { $blocks.Add((New-CippReportClearBox -Title 'No sender data' -Content 'Microsoft returned no top-sender breakdown for this window.')) }
    $blocks.Add((New-CippReportHeading -Title 'Top Spam Recipients'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'Unwanted mail does not spread evenly. A handful of addresses - usually the published ones, and the people whose names appear on the website - absorb most of it, and those same addresses are the ones a targeted attempt will use. Concentration here identifies exactly who benefits most from stricter policy and from being asked to be careful.'))
    if ($topSpam.Count -gt 0) {
        $blocks.Add((New-CippReportTable -Limit 10 -Columns @(@{ header = 'Recipient'; key = 'name'; width = 3 }, @{ header = 'Messages'; key = 'count'; width = 1 }) -Rows @($topSpam | ForEach-Object { @{ name = ($_.Name ?? $_.name ?? 'Unknown'); count = (num ($_.Count ?? $_.count)) } })))
    } else { $blocks.Add((New-CippReportClearBox -Title 'No concentrated spam targets' -Content 'No recipient stands out as absorbing spam over this window.')) }

    # -- Recommendations --
    $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What to do with these figures'))
    $blocks.Add((New-CippReportHeading -Title 'Priority Actions'))
    $blocks.Add((New-CippReportParagraph -Text "Ordered by what this window's data actually shows, rather than by a generic checklist."))
    $priority = [System.Collections.Generic.List[object]]::new()
    if ($threats -gt 0) { $priority.Add(@{ label = 'Review anti-phishing and anti-malware policy strength.'; text = "$(num $threats) messages were blocked as phishing or malware in this window. Confirm the tenant is on the current preset security policies, that impersonation protection lists the people who would actually be impersonated, and that Safe Links and Safe Attachments cover every mailbox rather than a pilot group." }) }
    if ($topSpam.Count -gt 0) { $priority.Add(@{ label = 'Give the most-targeted users stronger protection.'; text = 'The recipients listed in this report absorb a disproportionate share of unwanted mail. Priority accounts, tighter quarantine policy and a short conversation about what they are receiving cost little and are aimed exactly where the traffic is going.' }) }
    $priority.Add(@{ label = 'Verify SPF, DKIM and DMARC are published and enforcing.'; text = 'These records decide whether mail claiming to be from the domain is accepted elsewhere. A DMARC policy left at p=none reports abuse without stopping it, which means the organisation can be impersonated to its own customers regardless of how well inbound filtering performs.' })
    if ($transportRules -gt 0) { $priority.Add(@{ label = 'Audit the transport rules acting on mail.'; text = "Transport rules handled $(num $transportRules) messages here. Rules accumulate, outlive the reason they were written, and silently override filtering decisions - confirm each one is still wanted and that none bypasses protection for a sender that no longer needs the exception." }) }
    $i = 0; $priorityItems = foreach ($p in $priority) { $i++; @{ marker = "$i."; label = $p.label; text = $p.text } }
    $blocks.Add((New-CippReportBullets -Items @($priorityItems)))
    $blocks.Add((New-CippReportHeading -Title 'Keeping It That Way'))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ label = 'Review mail flow on a fixed cadence.'; text = 'These figures are only meaningful against previous ones. A monthly look establishes the normal shape of the traffic, which is what makes an abnormal month visible at a glance.' }
                @{ label = 'Watch the outbound share, not just the inbound.'; text = 'Inbound threat volume reflects the internet. Outbound volume reflects the organisation, so a change there is far more likely to mean something has gone wrong inside it.' }
                @{ label = 'Alert on the conditions, not the counts.'; text = 'Configure alert policies for outbound spam and unusual sending volume. A report read monthly finds a compromised mailbox weeks late; an alert finds it the same day.' }
                @{ label = 'Keep quarantine reviewed and released promptly.'; text = 'Filtering only holds if people trust it. Where legitimate mail sits in quarantine unattended, users route around the controls - and that habit costs more than the filtering saves.' }
            )))

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Email Traffic Review'
            coversubtitle      = "Where email at $($Data.TenantName) came from over the last $days days, how much of it was delivered, and what was stopped before it reached a mailbox."
            covermeta          = ("{0:N0} messages $([char]0x00B7) {1}% delivered $([char]0x00B7) {2:N0} threats caught" -f $totalMail, $goodPct, $threats)
            covermetanote      = "Mail hygiene: $hygiene"
            coverfooternote    = "Confidential $([char]0x2014) For Internal Use Only"
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "$($Data.TenantName) $([char]0x2014) Mail Flow"
        }
    }
}
