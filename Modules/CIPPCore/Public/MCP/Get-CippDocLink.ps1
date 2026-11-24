function Get-CippDocLink {
    <#
    .SYNOPSIS
        Derives the published docs.cipp.app URL, GitHub source URL and in-app route for a docs file.
    .DESCRIPTION
        The docs tree is a GitBook git-sync source. GitBook builds a page's URL from its place in
        docs/SUMMARY.md, not from its file path; -SlugMap (from Get-CippDocSlugMap) holds those URLs.
        A page missing from SUMMARY.md is not published, and falls back to its path with '.md' dropped.
        Three link forms come out of that:

          docs/setup/setting-up-cipp/install.md
            -> https://docs.cipp.app/setup/setting-up-cipp/install
            -> https://github.com/CyberDrain/CIPP/blob/dev/docs/setup/setting-up-cipp/install.md

          docs/user-documentation/identity/administration/groups/team.md   (nested under groups/group.md in SUMMARY.md)
            -> https://docs.cipp.app/user-documentation/identity/administration/groups/group/team

        Pages under 'user-documentation/' mirror the frontend's own routing, which is the same
        assumption _app.js already makes when it builds its "docs for this page" link. Only those
        pages get an AppPath; nothing else in the tree corresponds to a route.

        Anchors are GitBook's heading slugs (lowercased, non-alphanumerics collapsed to hyphens),
        which is what makes a chunk-level result deep-link to the exact section it matched rather
        than to the top of a 25 KB page.

        Only the docs URL follows SUMMARY.md. The GitHub URL always keeps the real repo path,
        because that is where the file actually lives. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # Path of the markdown file relative to the docs root, e.g. 'setup/setting-up-cipp/install.md'.
        [Parameter(Mandatory)]
        [string]$RelativePath,

        # Optional heading text to deep-link to within the page.
        [string]$Heading,

        # Published slug per docs-relative path, from Get-CippDocSlugMap.
        [System.Collections.Generic.Dictionary[string, string]]$SlugMap
    )

    $Clean = $RelativePath -replace '\\', '/' -replace '^\./', '' -replace '^/', ''
    $Slug = $null
    if ($SlugMap) { $null = $SlugMap.TryGetValue($Clean, [ref]$Slug) }

    if (-not $Slug) {
        # A README is the index of its folder; the docs root README publishes as /readme.
        $Slug = $Clean -replace '(?i)\.md$', ''
        if ($Slug -match '(?i)^README$') {
            $Slug = 'readme'
        } elseif ($Slug -match '(?i)/README$') {
            $Slug = $Slug -replace '(?i)/README$', ''
        }
    }

    $Anchor = if ($Heading) { Get-CippDocAnchor -Heading $Heading } else { '' }
    $Fragment = if ($Anchor) { "#$Anchor" } else { '' }

    $AppPath = if ($Slug -match '^user-documentation/(.+)$') { "/$($Matches[1])" } else { $null }

    return [ordered]@{
        docsUrl   = "https://docs.cipp.app/$Slug$Fragment"
        githubUrl = "https://github.com/CyberDrain/CIPP/blob/dev/docs/$Clean$Fragment"
        appPath   = $AppPath
        slug      = $Slug
        anchor    = $Anchor
    }
}

function Get-CippDocAnchor {
    <#
    .SYNOPSIS
        Converts a markdown heading to the anchor slug GitBook publishes for it.
    .DESCRIPTION
        Mirrors GitBook's slug rules: strip inline markdown, lowercase, drop anything that is not
        alphanumeric or a space/hyphen, then collapse whitespace runs to single hyphens. Apostrophes
        are removed rather than replaced, so "Confirm You've Met All Prerequisites" becomes
        'confirm-youve-met-all-prerequisites' and not 'confirm-you-ve-...'. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Heading)

    if ([string]::IsNullOrWhiteSpace($Heading)) { return '' }

    $Text = $Heading -replace '^#+\s*', ''
    # Inline markdown that renders away before the slug is taken: links keep their label only.
    $Text = $Text -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $Text = $Text -replace '[`*_~]', ''
    # Straight and typographic apostrophes both vanish rather than becoming separators.
    # Written as regex escapes, not literals: PowerShell reads a bare U+2019 as a quote
    # delimiter, so a literal here is one encoding round-trip away from a parser error.
    $Text = $Text -replace '[\u2018\u2019'']', ''
    $Text = $Text.ToLowerInvariant()
    $Text = $Text -replace '[^a-z0-9 \-]', ' '
    $Text = ($Text -replace '\s+', ' ').Trim()
    $Text = $Text -replace '[\s\-]+', '-'

    return $Text.Trim('-')
}

function Get-CippDocSlugMap {
    <#
    .SYNOPSIS
        Maps every page in docs/SUMMARY.md to the URL slug GitBook publishes it at.
    .DESCRIPTION
        GitBook serves a page at its parent page's URL plus its own name: the folder name for a
        README, the file name otherwise. A top-level page under a '## Group' heading starts from
        the first folder of its path. So groups/team.md nested under groups/group.md is served at
        groups/group/team, and email/resources/management/README.md nested under email/README.md
        is served at email/management. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DocsRoot)

    $Map = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Summary = Join-Path $DocsRoot 'SUMMARY.md'
    if (-not [System.IO.File]::Exists($Summary)) { return , $Map }

    $Parents = [System.Collections.Generic.List[object]]::new()
    foreach ($Line in [System.IO.File]::ReadAllLines($Summary)) {
        if ($Line.StartsWith('## ')) { $Parents.Clear(); continue }
        if ($Line -notmatch '^(\s*)\*\s+\[[^\]]*\]\(([^)\s]+\.md)(?:\s+"[^"]*")?\)') { continue }
        $Indent = $Matches[1].Length
        $Path = $Matches[2]
        while ($Parents.Count -and $Parents[$Parents.Count - 1].Indent -ge $Indent) { $Parents.RemoveAt($Parents.Count - 1) }

        $Segments = $Path -split '/'
        $Name = if ($Segments[-1] -ne 'README.md') { $Segments[-1] -replace '(?i)\.md$', '' } elseif ($Segments.Count -gt 1) { $Segments[-2] } else { 'readme' }
        $Slug = if ($Parents.Count) {
            "$($Parents[$Parents.Count - 1].Slug)/$Name"
        } elseif ($Segments.Count -gt 2 -or ($Segments.Count -eq 2 -and $Segments[1] -ne 'README.md')) {
            "$($Segments[0])/$Name"
        } else {
            $Name
        }

        $null = $Map.TryAdd($Path, $Slug)
        $Parents.Add([pscustomobject]@{ Indent = $Indent; Slug = $Slug })
    }
    return , $Map
}
