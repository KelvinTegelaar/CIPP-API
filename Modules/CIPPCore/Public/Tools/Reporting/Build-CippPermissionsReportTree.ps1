function Build-CippPermissionsReportTree {
    <#
    .SYNOPSIS
        Compose the SharePoint Permissions report as a component tree (server port of
        PermissionsReportButton.jsx).
    .PARAMETER Data
        Permissions data: summary (counts), assignments[], skippedSites[]. Returns @{ Blocks; Variables }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $summary = if ($Data.summary) { $Data.summary } else { @{} }
    # `?? @()` so a missing list is empty rather than @($null), which would count as one row.
    $assignments = @($Data.assignments ?? @())
    $skipped = @($Data.skippedSites ?? @())
    function nz($v) { if ($null -eq $v) { 0 } else { [int]$v } }
    function plural($c, $s, $p) { "$c $(if ($c -eq 1) { $s } else { if ($p) { $p } else { "${s}s" } })" }

    $score = (@(
            if ((nz $summary.broadClaimGrants) -gt 0) { 5 }
            if ((nz $summary.externalGrants) -gt 0) { 3 }
            if ((nz $summary.directFullControlGrants) -gt 0) { 2 }
            if ((nz $summary.uniquePermissionLibraries) -gt 0) { 1 }
        ) | Measure-Object -Sum).Sum
    $exposure = if ($score -ge 7) { 'High' } elseif ($score -ge 3) { 'Medium' } else { 'Low' }
    $dangerC = '#742A2A'; $warnC = '#744210'
    $sevColour = @{ High = $dangerC; Medium = $warnC; Low = '#22543D' }[$exposure]
    $claimLabels = @{ Everyone = 'Everyone (includes external users)'; EveryoneExceptExternal = 'Everyone except external users'; AllUsers = 'All Users' }

    $real = @($assignments | Where-Object { $_.principalId -and -not $_.isSystemManaged })
    $broad = @($real | Where-Object { $_.broadClaim })
    $external = @($real | Where-Object { $_.isGuest -eq $true })
    $fullCtl = @($real | Where-Object { $_.permissionLevel -eq 'Full Control' -and $_.principalType -ne 'SharePoint Group' })
    $libRows = @($real | Where-Object { $_.scope -eq 'Library' })
    $siteLabel = { param($r) if ($r.siteName) { $r.siteName } elseif ($r.siteUrl) { $r.siteUrl } else { 'Unnamed site' } }
    $scopeLabel = { param($r) if ($r.scope -eq 'Library') { "$(& $siteLabel $r) / $($r.libraryTitle)" } else { (& $siteLabel $r) } }

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'Who is allowed in, and how widely'))
    $blocks.Add((New-CippReportParagraph -Html ('<p>Permissions are set by administrators on a site or document library and decide who is structurally allowed in. They change rarely, which is what makes them worth auditing: a permission granted for one project stays in place indefinitely, and a permission granted to the whole organisation looks identical to one granted to a single team until somebody reads it. This report covers <b>{0}</b>.</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName))))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (nz $summary.broadClaimGrants); label = 'Tenant-Wide Grants'; colour = $(if ((nz $summary.broadClaimGrants) -gt 0) { $dangerC }) }
                @{ value = (nz $summary.externalGrants); label = 'External Grants'; colour = $(if ((nz $summary.externalGrants) -gt 0) { $warnC }) }
                @{ value = (nz $summary.directFullControlGrants); label = 'Direct Full Control'; colour = $(if ((nz $summary.directFullControlGrants) -gt 0) { $warnC }) }
                @{ value = (nz $summary.uniquePermissionLibraries); label = 'Detached Libraries' }
            )))
    $expText = switch ($exposure) {
        'High' { 'Content is reachable by people it was never meant for. A tenant-wide grant is present, which opens the content to the entire organisation regardless of who the site membership says should have it - and it is the most common reason material turns up unexpectedly in search results and AI assistant answers. Treat the findings below as immediate remediation work.' }
        'Medium' { 'Access extends past the intended audience in places. Each finding below is individually manageable, but each one widens what a single compromised account reaches.' }
        default { 'Permissions broadly match what the structure intends. No tenant-wide grants were found. Continue reviewing periodically, particularly after site or library changes.' }
    }
    $blocks.Add((New-CippReportAlertBox -Title "Permission Exposure: $exposure" -Colour $sevColour -Content $expText))
    $blocks.Add((New-CippReportInfoBox -Title 'What was examined' -Content ("{0} SharePoint sites and {1} document libraries were read, producing {2} permission assignments. Data is taken from the last completed sync, not read live." -f (nz $summary.sitesScanned), (nz $summary.librariesScanned), (nz $summary.totalAssignments))))
    $blocks.Add((New-CippReportInfoBox -Title 'What is not covered' -Content 'Permissions are reported as grant paths, not effective access - a group holding a permission is one entry and its members are not expanded, so a person may hold access that shows here only via their group. Permissions on individual folders and files are not enumerated. OneDrive personal sites are out of scope. Access handed out by sharing link is a separate path, covered by the Sharing Report.'))
    if ($skipped.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title ("$(plural $skipped.Count 'site') could not be read") -Colour $warnC -Content 'These sites could not be read on the most recent scan. Where a site was read successfully before, its earlier results are still shown and are as old as that scan; a site never read successfully contributes nothing. Either way, an absence of findings for these sites is not evidence of good configuration.'))
    }

    # -- Findings --
    $blocks.Add((New-CippReportPage -Title 'Findings' -Subtitle 'Permissions worth reviewing, most urgent first'))
    $blocks.Add((New-CippReportHeading -Title 'Finding 1: Tenant-Wide Grants'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content "SharePoint offers a handful of special audiences - Everyone, Everyone except external users, and All Users - that resolve to the whole organisation rather than to named people. A library carrying one is readable by every employee no matter what the site's membership says, and it is the single most common cause of data appearing in search results or AI assistant answers where it was not expected."))
    if ($broad.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title ("$(plural $broad.Count 'tenant-wide grant') found") -Colour $dangerC -Content 'Confirm the content is genuinely meant to be organisation-wide. If not, replace the grant with a specific group - one edit removes access for everyone who was never meant to have it.'))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Location'; key = 'location'; width = 2.4 }, @{ header = 'Audience'; key = 'audience'; width = 2 }, @{ header = 'Permission'; key = 'level'; width = 1.2 }) -Rows @($broad | ForEach-Object { @{ location = (& $scopeLabel $_); audience = ($claimLabels[$_.broadClaim] ?? $_.broadClaim); level = $_.permissionLevel } })))
    } else { $blocks.Add((New-CippReportClearBox -Title 'No tenant-wide grants found' -Content 'No site or library grants access to Everyone, Everyone except external users, or All Users.')) }
    $blocks.Add((New-CippReportHeading -Title 'Finding 2: External and Guest Access'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'Guest accounts holding permissions retain that access until somebody removes it - unlike a sharing link, nothing expires it. Guests from finished projects are a common source of standing access nobody is reviewing.'))
    if ($external.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title ("$(plural $external.Count 'grant') held by external identities") -Colour $warnC -Content 'Verify each guest still needs access and that the relationship is current.'))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Location'; key = 'location'; width = 2.2 }, @{ header = 'Identity'; key = 'identity'; width = 2.4 }, @{ header = 'Permission'; key = 'level'; width = 1.2 }) -Rows @($external | ForEach-Object { @{ location = (& $scopeLabel $_); identity = ($_.email ?? $_.title ?? $_.loginName); level = $_.permissionLevel } })))
    } else { $blocks.Add((New-CippReportClearBox -Title 'No external grants found' -Content 'No guest or external identity holds a permission on a scanned site or library.')) }

    # -- Findings continued --
    $blocks.Add((New-CippReportPage -Title 'Findings (continued)' -Subtitle 'Elevated rights and inheritance'))
    $blocks.Add((New-CippReportHeading -Title 'Finding 3: Directly Granted Full Control'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'Every site has an Owners group that holds Full Control by design, and that is expected. Full Control granted straight to a person or a directory group is different: it sits outside the membership structure, so it is not removed when someone leaves a team and it is easy to overlook when reviewing who administers a site.'))
    if ($fullCtl.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title (plural $fullCtl.Count 'direct Full Control grant') -Colour $warnC -Content "Move these into the site's Owners group where the access is legitimate, so membership changes take effect automatically."))
        $blocks.Add((New-CippReportTable -Columns @(@{ header = 'Location'; key = 'location'; width = 2.2 }, @{ header = 'Principal'; key = 'principal'; width = 2.2 }, @{ header = 'Type'; key = 'type'; width = 1.2 }) -Rows @($fullCtl | ForEach-Object { @{ location = (& $scopeLabel $_); principal = ($_.title ?? $_.email ?? $_.loginName); type = $_.principalType } })))
    } else { $blocks.Add((New-CippReportClearBox -Title 'Full Control is held through Owners groups' -Content "No user or directory group holds Full Control outside a site's Owners group.")) }
    $blocks.Add((New-CippReportHeading -Title 'Finding 4: Libraries With Their Own Permissions'))
    $blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'A library normally inherits from its site, so managing the site manages everything in it. A detached library keeps its own permissions and later site-level changes no longer reach it. That is legitimate when deliberate and a blind spot when not - removing somebody from the site does not remove them here.'))
    if ((nz $summary.uniquePermissionLibraries) -gt 0) {
        $blocks.Add((New-CippReportParagraph -Text ("{0} of {1} libraries no longer inherit from their site. Their assignments are listed in the appendix. Review whether each detachment was intentional and is still needed." -f (nz $summary.uniquePermissionLibraries), (nz $summary.librariesScanned))))
    } else { $blocks.Add((New-CippReportClearBox -Title 'All libraries inherit from their site' -Content 'Every scanned library takes its permissions from its site, so site-level access management covers them all.')) }

    # -- Recommendations --
    $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What to do about the findings'))
    $blocks.Add((New-CippReportHeading -Title 'Priority Actions'))
    $blocks.Add((New-CippReportParagraph -Text 'Ordered by how much access each removes relative to the effort involved.'))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ marker = '1.'; label = 'Replace tenant-wide grants.'; text = 'Swap Everyone and All Users grants for a specific group. This is the highest-value change available: a single edit removes access for everyone who was never meant to have it.' }
                @{ marker = '2.'; label = 'Review guest permissions.'; text = 'Guests keep permissions indefinitely. Remove those whose projects have ended, and prefer time-boxed sharing for new external work.' }
                @{ marker = '3.'; label = 'Move direct Full Control into Owners groups.'; text = 'Administrative rights held through the Owners group follow joiners and leavers. Held directly, they have to be remembered.' }
                @{ marker = '4.'; label = 'Re-inherit libraries detached without reason.'; text = "Restoring inheritance brings a library back under site-level management. Only do this where the detachment was not deliberate - it discards the library's own permissions." }
                @{ marker = '5.'; label = 'Prefer groups over individual grants.'; text = 'A permission held by a group updates itself as people join and leave. One held by a person does not.' }
            )))
    $blocks.Add((New-CippReportHeading -Title 'Keeping It That Way'))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ label = 'Re-run this review regularly.'; text = 'Permissions drift as projects start and end. A periodic review catches drift while it is still small.' }
                @{ label = 'Manage access at the site, not the library.'; text = 'Leaving libraries inherited keeps one place to look when somebody joins or leaves.' }
                @{ label = 'Check effective access, not just the lists.'; text = 'A group holding Edit says nothing about who is in it. Use the access check on a site to confirm what a specific person can actually reach.' }
                @{ label = 'Avoid tenant-wide audiences by default.'; text = 'Where content genuinely is organisation-wide, say so deliberately and review it, rather than reaching for Everyone because it is convenient.' }
            )))

    # -- Appendix --
    $blocks.Add((New-CippReportPage -Title 'Appendix: Detached Library Permissions' -Subtitle 'Assignments on libraries that no longer inherit from their site'))
    $blocks.Add((New-CippReportTable -Limit 40 -EmptyText 'No libraries hold their own permissions.' -Columns @(@{ header = 'Site'; key = 'site'; width = 1.8 }, @{ header = 'Library'; key = 'library'; width = 1.6 }, @{ header = 'Principal'; key = 'principal'; width = 2.2 }, @{ header = 'Permission'; key = 'level'; width = 1.2 }) -Rows @($libRows | ForEach-Object { @{ site = (& $siteLabel $_); library = $_.libraryTitle; principal = ($_.title ?? $_.email ?? $_.loginName); level = $_.permissionLevel } })))

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Access Review'
            coversubtitle      = "Who is structurally allowed into SharePoint sites and document libraries at $($Data.TenantName), and where that access reaches further than intended."
            covermeta          = ("{0} sites $([char]0x00B7) {1} libraries $([char]0x00B7) {2} permission assignments" -f (nz $summary.sitesScanned), (nz $summary.librariesScanned), (nz $summary.totalAssignments))
            covermetanote      = "Permission exposure: $exposure"
            coverfooternote    = "Confidential $([char]0x2014) For Internal Use Only"
            coverfallbackimage = '/reportImages/soc.jpg'
            footerlabel        = "$($Data.TenantName) $([char]0x2014) SharePoint Permissions"
        }
    }
}
