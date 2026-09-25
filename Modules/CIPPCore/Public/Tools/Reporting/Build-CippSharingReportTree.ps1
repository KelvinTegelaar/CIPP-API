function Build-CippSharingReportTree {
    <#
    .SYNOPSIS
        Compose the SharePoint/OneDrive Sharing report as a component tree (server port of
        SharingReportButton.jsx).
    .DESCRIPTION
        Pure composition from already-gathered sharing data. Returns @{ Blocks; Variables }: the
        component nodes for ConvertTo-CippReportPdf and the cover/footer report variables.
    .PARAMETER Data
        Sharing data: summary (counts), links[], topRecipients[], topLibraries[].
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $summary = if ($Data.summary) { $Data.summary } else { @{} }
    # `?? @()` so a missing list is empty rather than @($null), which would render as one blank row.
    $links = @($Data.links ?? @())
    $topRecipients = @($Data.topRecipients ?? @())
    $topLibraries = @($Data.topLibraries ?? @())
    function nz($v) { if ($null -eq $v) { 0 } else { [int]$v } }
    function plural($c, $s, $p) { "$c $(if ($c -eq 1) { $s } else { if ($p) { $p } else { "${s}s" } })" }
    function joinList($v) { if ($v -is [array]) { $v -join ', ' } else { [string]$v } }

    # Exposure grade (client assessExposure).
    $score = (@(
            if ((nz $summary.anonymousEditLinks) -gt 0) { 5 }
            if ((nz $summary.neverExpiringAnonymous) -gt 0) { 3 }
            if ((nz $summary.anonymousLinks) -gt 0) { 2 }
            if ((nz $summary.folderShares) -gt 0) { 2 }
            if ((nz $summary.externalLinks) -gt 0) { 1 }
        ) | Measure-Object -Sum).Sum
    $exposure = if ($score -ge 7) { 'High' } elseif ($score -ge 3) { 'Medium' } else { 'Low' }
    $dangerC = '#742A2A'; $warnC = '#744210'
    $sevColour = @{ High = $dangerC; Medium = $warnC; Low = '#22543D' }[$exposure]

    $canEdit = { param($r) (joinList $r.roles) -match 'write|owner' }
    $anonEdit = @($links | Where-Object { $_.classification -eq 'Anonymous' -and (& $canEdit $_) })
    $neverExp = @($links | Where-Object { $_.classification -eq 'Anonymous' -and -not $_.expirationDateTime })
    $folderShares = @($links | Where-Object { $_.itemType -eq 'Folder' -and @('Anonymous', 'External') -contains $_.classification })
    $externalRows = @($links | Where-Object { $_.classification -eq 'External' })
    $locationOf = { param($r) "$(if ($r.siteName) { $r.siteName } elseif ($r.siteUrl) { $r.siteUrl } else { 'Unknown site' })$(if ($r.driveName) { " / $($r.driveName)" })" }
    $expiryOf = { param($r) if ($r.expirationDateTime) { ([datetime]$r.expirationDateTime).ToString('M/d/yyyy') } else { 'Never' } }

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'What has been shared, and how far it reaches'))
    $blocks.Add((New-CippReportParagraph -Html ('<p>Sharing links are created by users on individual files and folders. They hand out access outside the permission structure an administrator sets on a site or library, they accumulate quietly as people work, and nothing prompts anyone to review them. This report covers what exists today across SharePoint and OneDrive in <b>{0}</b>.</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName))))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (nz $summary.anonymousEditLinks); label = 'Anonymous & Editable'; colour = $(if ((nz $summary.anonymousEditLinks) -gt 0) { $dangerC }) }
                @{ value = (nz $summary.neverExpiringAnonymous); label = 'Anonymous, No Expiry'; colour = $(if ((nz $summary.neverExpiringAnonymous) -gt 0) { $dangerC }) }
                @{ value = (nz $summary.folderShares); label = 'Shared Folders'; colour = $(if ((nz $summary.folderShares) -gt 0) { $warnC }) }
                @{ value = (nz $summary.externalRecipients); label = 'External Recipients'; colour = $(if ((nz $summary.externalRecipients) -gt 0) { $warnC }) }
            )))
    $expText = switch ($exposure) {
        'High' { 'Content is reachable by people who cannot be identified. Anonymous links work for anyone holding them, with no sign-in and no record of use - and where those links also allow editing, changes are attributed to nobody. Treat the findings below as immediate remediation work.' }
        'Medium' { 'Sharing extends beyond the intended audience in places. Each finding below is individually manageable, but every open link widens what a single forwarded message can expose.' }
        default { 'No high-risk sharing was found. Links are scoped and time-bounded. Continue reviewing periodically, since sharing accumulates as projects come and go.' }
    }
    $blocks.Add((New-CippReportAlertBox -Title "Sharing Exposure: $exposure" -Colour $sevColour -Content $expText))
    $blocks.Add((New-CippReportInfoBox -Title 'What was examined' -Content ("{0} sharing links and external shares across {1} SharePoint sites, {2} Teams-connected sites and {3} OneDrive accounts, covering {4} distinct shared items. Data is taken from the last completed sync, not read live." -f (nz $summary.totalLinks), (nz $summary.sharePointSites), (nz $summary.teamsSites), (nz $summary.oneDriveAccounts), (nz $summary.itemsShared))))
    $blocks.Add((New-CippReportInfoBox -Title 'What is not covered' -Content 'This report covers sharing links only. Permissions granted on a site or document library are a separate access path, governed differently, and are covered by the Permissions Report. A clean result here does not mean access is restricted - it means nothing has been shared out by link.'))

    # -- Findings --
    $blocks.Add((New-CippReportPage -Title 'Findings' -Subtitle 'Shares worth reviewing, most urgent first'))
    $blocks.Add((New-CippReportHeading -Title 'Finding 1: Anonymous Links That Allow Editing'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'An anonymous link works for anyone who holds it - no sign-in, no record of who used it. When that link also grants editing, anyone it has been forwarded to can change or delete the content, and the change is attributed to nobody. This is the only combination that allows untraceable modification.'))
    if ($anonEdit.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title (plural $anonEdit.Count 'anonymous editable link') -Colour $dangerC -Content 'Revoke these, or downgrade them to view-only where the sharing is still needed.'))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Item'; key = 'item'; width = 2.4 }, @{ header = 'Location'; key = 'location'; width = 2 }, @{ header = 'Expires'; key = 'expires'; width = 1 }) -Rows @($anonEdit | ForEach-Object { @{ item = $_.fileName; location = (& $locationOf $_); expires = (& $expiryOf $_) } })))
    } else {
        $blocks.Add((New-CippReportClearBox -Title 'No anonymous editable links' -Content 'No anonymous link grants write access.'))
    }
    $blocks.Add((New-CippReportHeading -Title 'Finding 2: Anonymous Links That Never Expire'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'A link with no expiry date stays live indefinitely, long after the reason for sharing has passed. Expiry is the only control that withdraws this access without somebody remembering to do it.'))
    if ($neverExp.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title ("$(plural $neverExp.Count 'anonymous link') with no expiry") -Colour $warnC -Content 'Set a tenant-level default expiry so this cannot recur, then revoke the existing links that are no longer needed.'))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Item'; key = 'item'; width = 2.4 }, @{ header = 'Location'; key = 'location'; width = 2 }, @{ header = 'Permission'; key = 'roles'; width = 1 }) -Rows @($neverExp | ForEach-Object { @{ item = $_.fileName; location = (& $locationOf $_); roles = (joinList $_.roles) } })))
    } else {
        $blocks.Add((New-CippReportClearBox -Title 'All anonymous links expire' -Content 'Every anonymous link has an expiry date set.'))
    }

    # -- Findings continued --
    $blocks.Add((New-CippReportPage -Title 'Findings (continued)' -Subtitle 'Reach and recipients'))
    $blocks.Add((New-CippReportHeading -Title 'Finding 3: Shared Folders'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content "Sharing a folder shares everything inside it, including anything added later. The recipient's access grows over time without anyone re-approving it, which is the main way a small share quietly becomes a large one."))
    if ($folderShares.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title ("$(plural $folderShares.Count 'folder') shared externally or anonymously") -Colour $warnC -Content 'Check what each folder holds now, not what it held when it was shared.'))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Folder'; key = 'item'; width = 2.2 }, @{ header = 'Location'; key = 'location'; width = 2 }, @{ header = 'Audience'; key = 'audience'; width = 1.2 }) -Rows @($folderShares | ForEach-Object { @{ item = $_.fileName; location = (& $locationOf $_); audience = $_.classification } })))
    } else {
        $blocks.Add((New-CippReportClearBox -Title 'No externally shared folders' -Content 'External and anonymous shares point at individual files rather than folders.'))
    }
    $blocks.Add((New-CippReportHeading -Title 'Finding 4: External Recipients'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'Every external recipient is a person outside the organisation holding access that was granted individually, usually for a specific piece of work. Nothing withdraws it when that work ends.'))
    if ($topRecipients.Count -gt 0) {
        $blocks.Add((New-CippReportParagraph -Text ("{0} hold shared content, across {1}. The most frequent are listed below." -f (plural (nz $summary.externalRecipients) 'external identity' 'external identities'), (plural $externalRows.Count 'share'))))
        $blocks.Add((New-CippReportTable -Limit 15 -Columns @(@{ header = 'Recipient'; key = 'recipient'; width = 3 }, @{ header = 'Shares'; key = 'shares'; width = 1 }) -Rows @($topRecipients | ForEach-Object { @{ recipient = $_.recipient; shares = "$($_.links)" } })))
    } else {
        $blocks.Add((New-CippReportClearBox -Title 'No external recipients' -Content 'Nothing has been shared with an identity outside the organisation.'))
    }
    if ($topLibraries.Count -gt 0) {
        $blocks.Add((New-CippReportHeading -Title 'Where Sharing Concentrates'))
        $blocks.Add((New-CippReportParagraph -Text 'The libraries below account for the most sharing links. Concentration is not a problem in itself, but it shows where a review will have the most effect.'))
        $blocks.Add((New-CippReportTable -Limit 10 -Columns @(@{ header = 'Library'; key = 'library'; width = 3 }, @{ header = 'Links'; key = 'links'; width = 1 }) -Rows @($topLibraries | ForEach-Object { @{ library = $_.library; links = "$($_.links)" } })))
    }

    # -- Recommendations --
    $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What to do about the findings'))
    $blocks.Add((New-CippReportHeading -Title 'Priority Actions'))
    $blocks.Add((New-CippReportParagraph -Text 'Ordered by how much exposure each removes relative to the effort involved.'))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ marker = '1.'; label = 'Revoke or downgrade anonymous editable links.'; text = 'Anonymous plus editable is the only combination allowing untracked changes. Switching to view-only keeps the sharing working while removing the ability to alter content.' }
                @{ marker = '2.'; label = 'Set a default expiry for anonymous links.'; text = 'A tenant-level expiry policy stops never-expiring links being created again. This fixes the cause rather than the instances, so the problem does not rebuild.' }
                @{ marker = '3.'; label = 'Review folder-level external shares.'; text = 'Share specific files where practical. A folder share keeps granting access to content that did not exist when it was approved.' }
                @{ marker = '4.'; label = 'Review long-standing external recipients.'; text = 'Revoke shares belonging to finished engagements. External access has no natural end unless someone gives it one.' }
                @{ marker = '5.'; label = 'Require sign-in where the audience is known.'; text = 'A link scoped to specific people records who opened it. Anonymous links cannot be attributed to anyone.' }
            )))
    $blocks.Add((New-CippReportHeading -Title 'Keeping It That Way'))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ label = 'Re-run this review regularly.'; text = 'Sharing accumulates continuously. A periodic review catches it while the list is still short.' }
                @{ label = 'Set sharing defaults at tenant and site level.'; text = 'Default link type, expiry and permitted domains stop the riskiest shares being created at all, which is far cheaper than finding them later.' }
                @{ label = 'Restrict anonymous links to view-only.'; text = 'If anonymous sharing is needed at all, removing the edit option eliminates untraceable changes without blocking the sharing itself.' }
                @{ label = 'Password-protect sensitive shares.'; text = 'A password meaningfully narrows who can use a link that has been forwarded on.' }
            )))

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Data Sharing Review'
            coversubtitle      = "What has been shared out of SharePoint and OneDrive at $($Data.TenantName), who it reaches, and which of those shares are worth acting on."
            covermeta          = ("{0} sharing links $([char]0x00B7) {1} items $([char]0x00B7) {2} external recipients" -f (nz $summary.totalLinks), (nz $summary.itemsShared), (nz $summary.externalRecipients))
            covermetanote      = "Sharing exposure: $exposure"
            coverfooternote    = "Confidential $([char]0x2014) For Internal Use Only"
            coverfallbackimage = '/reportImages/glasses.jpg'
            footerlabel        = "$($Data.TenantName) $([char]0x2014) SharePoint & OneDrive Sharing"
        }
    }
}
