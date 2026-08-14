function Get-CippDocLink {
    <#
    .SYNOPSIS
        Derives the published docs.cipp.app URL, GitHub source URL and in-app route for a docs file.
    .DESCRIPTION
        The docs tree is a GitBook git-sync source, so a page's published URL is its file path with
        the '.md' dropped - there is no slug table to consult. Three link forms come out of that:

          docs/setup/setting-up-cipp/install.md
            -> https://docs.cipp.app/setup/setting-up-cipp/install
            -> https://github.com/CyberDrain/CIPP/blob/dev/docs/setup/setting-up-cipp/install.md

          docs/setup/setting-up-cipp/README.md   (a section index)
            -> https://docs.cipp.app/setup/setting-up-cipp

        Pages under 'user-documentation/' mirror the frontend's own routing one-for-one, which is
        the same assumption _app.js:259 already makes when it builds its "docs for this page" link.
        That makes the mapping reversible: a doc knows which CIPP screen it documents, and a screen
        can be traced back to its doc. Only paths under user-documentation get an AppPath; nothing
        else in the tree corresponds to a route.

        Anchors are GitBook's heading slugs (lowercased, non-alphanumerics collapsed to hyphens),
        which is what makes a chunk-level result deep-link to the exact section it matched rather
        than to the top of a 25 KB page.

        One rule is not guessable from the path alone: a folder with no README.md is a grouping
        folder, not a page, and GitBook drops it from the URL entirely. 'email/resources' has no
        README and publishes nothing, so its children move up a level -
        email/resources/management/equipment/edit.md is served at email/management/equipment/edit.
        Without this, seven pages get confidently wrong links. -SectionFolder supplies the set of
        folders that do own a README; the index builder computes it once for the whole tree.

        Only the docs URL is rewritten. The GitHub URL always keeps the real repo path, because
        that is where the file actually lives. Not an HTTP entrypoint.
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

        # Folder paths (relative to the docs root, '/'-separated) that contain a README.md.
        # Any ancestor folder absent from this set is elided from the published URL.
        [System.Collections.Generic.HashSet[string]]$SectionFolder
    )

    $Clean = $RelativePath -replace '\\', '/' -replace '^\./', '' -replace '^/', ''
    $Slug = $Clean -replace '(?i)\.md$', ''

    # A README is the index of the folder it sits in, so it publishes at the folder's own URL.
    # The docs root README is the site root, which GitBook publishes as /readme rather than /.
    if ($Slug -match '(?i)^README$') {
        $Slug = 'readme'
    } elseif ($Slug -match '(?i)/README$') {
        $Slug = $Slug -replace '(?i)/README$', ''
    }

    # Drop grouping folders. The final segment is the page itself and always survives. A
    # top-level folder is a SUMMARY.md '## Group' and always contributes its slug even though
    # it owns no README ('setup' has none, yet every setup page is served under /setup).
    # Below that, a folder only earns a URL slot by owning a README.
    if ($SectionFolder -and $Slug -ne 'readme') {
        $Segments = @($Slug -split '/')
        if ($Segments.Count -gt 1) {
            $Kept = [System.Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $Segments.Count - 1; $i++) {
                $Folder = ($Segments[0..$i] -join '/')
                if ($i -eq 0 -or $SectionFolder.Contains($Folder)) { $Kept.Add($Segments[$i]) }
            }
            $Kept.Add($Segments[-1])
            $Slug = $Kept -join '/'
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
