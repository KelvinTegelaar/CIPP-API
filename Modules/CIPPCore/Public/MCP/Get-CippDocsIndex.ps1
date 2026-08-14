function Get-CippDocsIndex {
    <#
    .SYNOPSIS
        Builds, once per host, the searchable index over the shipped CIPP documentation tree.
    .DESCRIPTION
        Backs the SearchDocs / GetDoc MCP tools. The docs are shipped in the image (see the docs/
        COPY in build/Dockerfile) rather than fetched from docs.cipp.app, because there is no
        GitBook search API, llms-full.txt is capped at 100 of the 427 pages, and a crawl would put
        an outbound-internet dependency in the request path. Shipping them also version-matches the
        docs to the running build, and results still carry live docs.cipp.app links, so a caller
        who needs the very latest text can always follow one.

        This function does discovery, markdown parsing and link derivation; CIPPSharp's
        CIPP.DocsIndex owns tokenisation, the postings map and scoring. That split is deliberate:
        the parsing is cheap and reads better in PowerShell, while tokenising 2 MB of prose in
        PowerShell measured at 26 seconds against well under a second in .NET. Just as importantly
        the C# index is a host-scoped static, so it is built once for every worker on the host
        rather than once per runspace - the IsBuilt check below is what lets the other workers skip
        all of this.

        Pages are split into chunks at '##'/'###' headings. A chunk, not a page, is the unit of
        retrieval: pages here run to 25 KB, and returning a whole one to answer a question about a
        single section wastes the caller's context and buries the answer. Each chunk carries its
        heading anchor, so a hit deep-links to the exact section.

        Two page classes are excluded outright rather than ranked down:
          - legacy-setup-hidden-from-nav/  33 superseded 'Copy of ...' duplicates of the setup
                                           guide. Near-identical text to the live pages, so they
                                           would double every setup hit with a dead link.
          - .gitbook/includes/             reusable snippets that are not pages at all.
        Pages that exist but GitBook does not publish keep a GitHub link and get no docsUrl,
        rather than being handed a docs.cipp.app URL that 404s.

        Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # Overrides the docs root. Defaults to the shipped copy, then the repo tree for local dev.
        [string]$DocsRoot,
        [switch]$Force
    )

    if (-not $DocsRoot) { $DocsRoot = Get-CippDocsRoot }
    if (-not $DocsRoot) {
        throw [pscustomobject]@{ code = -32603; message = 'CIPP documentation not found in this deployment; docs search is unavailable.' }
    }

    $DocsRoot = (Resolve-Path -LiteralPath $DocsRoot).Path.TrimEnd('\', '/')

    if (-not $Force -and [CIPP.DocsIndex]::IsBuilt($DocsRoot)) {
        return Get-CippDocsIndexStatus -DocsRoot $DocsRoot
    }

    $RootLength = $DocsRoot.Length

    # Folders owning a README are real pages and contribute a URL segment; the rest are elided.
    $SectionFolder = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Readme in [System.IO.Directory]::EnumerateFiles($DocsRoot, 'README.md', [System.IO.SearchOption]::AllDirectories)) {
        $Dir = [System.IO.Path]::GetDirectoryName($Readme)
        if ($Dir.Length -le $RootLength) { continue }
        $SectionFolder.Add(($Dir.Substring($RootLength).TrimStart('\', '/') -replace '\\', '/')) | Out-Null
    }

    # What GitBook actually publishes, so the index never invents a link.
    $Published = Get-CippDocsPublishedSet

    $Builder = [CIPP.DocsIndex]::BeginBuild($DocsRoot)

    foreach ($FullPath in [System.IO.Directory]::EnumerateFiles($DocsRoot, '*.md', [System.IO.SearchOption]::AllDirectories)) {
        $Rel = $FullPath.Substring($RootLength).TrimStart('\', '/') -replace '\\', '/'

        if ($Rel -eq 'SUMMARY.md') { continue }
        if ($Rel -like '.gitbook/*') { continue }
        if ($Rel -like 'legacy-setup-hidden-from-nav/*') { continue }

        $Parsed = ConvertFrom-CippDocMarkdown -Markdown ([System.IO.File]::ReadAllText($FullPath)) -RelativePath $Rel
        $Link = Get-CippDocLink -RelativePath $Rel -SectionFolder $SectionFolder

        $IsPublished = if ($null -eq $Published) { $true } else { $Published.Contains($Link.slug) }

        $PageIndex = $Builder.AddPage(
            $Rel,
            $Parsed.Title,
            $Parsed.Description,
            $Parsed.Breadcrumb,
            $Link.slug,
            $(if ($IsPublished) { $Link.docsUrl } else { $null }),
            $Link.githubUrl,
            $(if ($IsPublished) { $Link.appPath } else { $null }),
            $IsPublished)

        foreach ($Chunk in $Parsed.Chunks) {
            if ([string]::IsNullOrWhiteSpace($Chunk.Text) -and -not $Chunk.Heading) { continue }
            $Anchor = if ($Chunk.Heading) { Get-CippDocAnchor -Heading $Chunk.Heading } else { '' }
            $Builder.AddChunk($PageIndex, $Chunk.Heading, $Anchor, $Chunk.Text)
        }
    }

    [CIPP.DocsIndex]::CommitBuild($Builder)

    $Status = Get-CippDocsIndexStatus -DocsRoot $DocsRoot
    Write-Information "[MCP] docs index built: $($Status.pageCount) pages, $($Status.chunkCount) chunks, $($Status.termCount) terms from $DocsRoot"
    return $Status
}

function Get-CippDocsIndexStatus {
    <#
    .SYNOPSIS
        Reports the current host-scoped docs index counts.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$DocsRoot)

    return [ordered]@{
        docsRoot   = $DocsRoot
        pageCount  = [CIPP.DocsIndex]::PageCount
        chunkCount = [CIPP.DocsIndex]::ChunkCount
        termCount  = [CIPP.DocsIndex]::TermCount
    }
}

function Get-CippDocsRoot {
    <#
    .SYNOPSIS
        Locates the documentation tree, in the container or in a source checkout.
    .DESCRIPTION
        Checks CIPPDocsPath first (the dev compose files set it), then the image's own
        $env:CIPPRootPath/Docs, then the repo layout so local dev and Pester runs work without a
        build. Returns $null when none holds documentation.

        A candidate has to actually contain markdown to win, which is not the pedantry it looks
        like. Bind-mounting the docs at /app/API/Docs - inside the ../backend mount - makes Docker
        create the nested mountpoint on the *host*, leaving an empty backend/Docs in the working
        tree. That directory then satisfies a bare existence check and shadows the real docs for
        everything running outside the container, so every search silently returns nothing against
        a perfectly healthy index of zero pages. The dev mount now lives at /app/Docs to avoid
        creating it at all; this check is the backstop. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:CIPPDocsPath) { $Candidates.Add($env:CIPPDocsPath) }
    if ($env:CIPPRootPath) {
        foreach ($Relative in 'Docs', '../docs', '../../docs') {
            $Candidates.Add((Join-Path -Path $env:CIPPRootPath -ChildPath $Relative))
        }
    }

    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { continue }
        # Select-Object -First 1 short-circuits the enumeration, so this stops at the first hit
        # rather than walking the whole tree.
        $Markdown = @([System.IO.Directory]::EnumerateFiles($Candidate, '*.md', [System.IO.SearchOption]::AllDirectories) |
                Select-Object -First 1)
        if ($Markdown.Count -gt 0) { return $Candidate }
    }
    return $null
}

function Get-CippDocsPublishedSet {
    <#
    .SYNOPSIS
        Reads the set of slugs GitBook actually publishes, from the committed snapshot.
    .DESCRIPTION
        A page can exist in docs/ and still not be live: nine current pages under
        setup/implementation-guide/your-route-to-a-secure-tenant/ are in SUMMARY.md but
        unpublished, so SUMMARY is not the discriminator. docs.cipp.app/llms.txt is the only
        authoritative statement, and Config/DocsPublishedPages.txt is a snapshot of it - which
        keeps the check offline, so the index never has to guess and never hands back a
        docs.cipp.app URL that 404s.

        The container build refreshes that snapshot from the live site (the build-docspages stage),
        so the committed copy is a fallback rather than the source of truth - it is what ships only
        when the fetch fails. Refresh the committed one with
        build/tools/Update-DocsPublishedPages.ps1.

        Returns $null when the snapshot is missing, which the caller reads as 'assume everything is
        published' - a stale link is a better failure than no docs search at all.
        Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $SnapshotPath = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config/DocsPublishedPages.txt'
    if (-not (Test-Path -LiteralPath $SnapshotPath)) { return $null }

    $Set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Line in [System.IO.File]::ReadAllLines($SnapshotPath)) {
        $Trimmed = $Line.Trim()
        if (-not $Trimmed -or $Trimmed.StartsWith('#')) { continue }
        $Set.Add($Trimmed) | Out-Null
    }
    return $(if ($Set.Count -gt 0) { $Set } else { $null })
}
