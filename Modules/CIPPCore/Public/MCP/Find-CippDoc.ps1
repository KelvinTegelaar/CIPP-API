function Find-CippDoc {
    <#
    .SYNOPSIS
        Searches the CIPP documentation and returns ranked, deep-linked sections.
    .DESCRIPTION
        Backs the SearchDocs core tool. Scoring is BM25 over CIPPSharp's inverted index, with
        three expansions layered on top of the caller's literal terms. None of them is a vector
        model - CIPP has no embedding provider, and requiring an API key to search the docs would
        be a poor trade - but together they cover most of what a caller means rather than types:

          - Domain synonyms (Config/DocsSynonyms.json), damped to 0.55. This is the one that
            matters: 'CA policy' reaches pages that only ever write 'conditional access'.
          - Fuzzy vocabulary matching, damped to 0.4, for terms the corpus does not contain at
            all. 'conditonal' is a typo, not a different question.
          - Path queries. A query that looks like a CIPP route ('/identity/administration/users')
            is matched against the page's own appPath, so an agent looking at a screen can ask for
            that screen's documentation directly.

        The caller is itself a model and rephrases well, so the remaining gap to true semantic
        recall is smaller in practice than it looks. Ranking stays behind this one function and
        CIPP.DocsIndex.Search, which is where an embedding reranker would slot in if one ever
        becomes available.

        Results are sections, not whole pages, and carry the heading anchor so the link lands on
        the part that matched. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        # Restrict to a subtree, e.g. 'user-documentation/identity' or a CIPP route.
        [string]$Path,
        [int]$Limit = 8
    )

    if ($Limit -lt 1) { $Limit = 8 }
    if ($Limit -gt 25) { $Limit = 25 }

    $null = Get-CippDocsIndex

    if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($Path)) {
        return [ordered]@{
            error = 'Provide a query (keywords or a question) and/or a path to scope the search.'
            hint  = 'Example: { "query": "how do I set up GDAP" } or { "path": "/identity/administration/users" }.'
        }
    }

    # A bare path with no keywords: return the pages under it directly.
    if ([string]::IsNullOrWhiteSpace($Query)) {
        $ByPath = [CIPP.DocsIndex]::ByPath($Path, $Limit)
        if ($ByPath.MatchCount -eq 0) {
            return [ordered]@{
                matchCount = 0
                results    = @()
                hint       = "No documentation page matches path '$Path'. Search by keywords instead, or drop the path filter."
            }
        }
        return [ordered]@{
            matchCount = $ByPath.MatchCount
            results    = @($ByPath.Hits | ForEach-Object { ConvertTo-CippDocSearchResult -Hit $_ })
            hint       = 'Matched by path. Call GetDoc with a result''s path for the full page text.'
        }
    }

    $Primary = @(ConvertTo-CippDocToken -Text $Query)
    if ($Primary.Count -eq 0) {
        return [ordered]@{
            matchCount = 0
            results    = @()
            hint       = 'The query reduced to no searchable terms. Try more specific keywords.'
        }
    }

    # Domain expansion happens here rather than in C# because the map is CIPP configuration,
    # not an indexing concern; the index just takes the extra terms and damps them.
    $Synonyms = Get-CippDocSynonym
    $Expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($Token in $Primary) {
        foreach ($Phrase in @($Synonyms[$Token])) {
            if (-not $Phrase) { continue }
            foreach ($Term in (ConvertTo-CippDocToken -Text $Phrase)) {
                if ($Term -notin $Primary) { $Expanded.Add($Term) }
            }
        }
    }

    $Search = [CIPP.DocsIndex]::Search([string[]]$Primary, [string[]]$Expanded.ToArray(), $Path, $Limit)

    if ($Search.MatchCount -eq 0) {
        $Response = [ordered]@{ matchCount = 0; results = @() }
        if ($Search.Suggestions.Count -gt 0) {
            $Response['suggestions'] = @($Search.Suggestions)
            $Response['hint'] = 'Nothing matched. The suggestions are the closest terms that do appear in the docs - try one of those.'
        } else {
            $Response['hint'] = 'Nothing matched. Try broader keywords, or the words a page would actually use.'
        }
        return $Response
    }

    Write-Information "[MCP] SearchDocs query='$Query' path='$Path' -> $($Search.MatchCount) sections, returning $($Search.Hits.Count)"

    return [ordered]@{
        matchCount = $Search.MatchCount
        results    = @($Search.Hits | ForEach-Object { ConvertTo-CippDocSearchResult -Hit $_ })
        hint       = 'Each result deep-links to the section that matched. Call GetDoc with a result''s path for the page''s full text.'
    }
}

function ConvertTo-CippDocSearchResult {
    <#
    .SYNOPSIS
        Shapes a CIPPSharp search hit into the object returned to the MCP caller.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Hit)

    $Result = [ordered]@{
        title   = $Hit.Title
        section = $Hit.Section
        path    = $Hit.Path
        excerpt = $Hit.Excerpt
        docsUrl = $Hit.DocsUrl
    }
    if (-not $Hit.Published) {
        $Result['note'] = 'Not published on docs.cipp.app; use the GitHub link.'
    }
    $Result['githubUrl'] = $Hit.GitHubUrl
    if ($Hit.AppPath) { $Result['appPath'] = $Hit.AppPath }
    $Result['breadcrumb'] = $Hit.Breadcrumb
    if ($Hit.Score -gt 0) { $Result['score'] = $Hit.Score }

    return $Result
}

function Get-CippDocSynonym {
    <#
    .SYNOPSIS
        Loads and caches the docs query-expansion map, keyed by stemmed token.
    .DESCRIPTION
        Config/DocsSynonyms.json is authored with ordinary words; the keys are stemmed here with
        the same rule the indexer uses, so an author does not have to predict the stemmer. A
        missing or malformed file degrades to no expansion rather than breaking search.
        Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($script:CippDocSynonym -and -not $Force) { return $script:CippDocSynonym }

    $Map = @{}
    $Path = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config/DocsSynonyms.json'
    if (Test-Path -LiteralPath $Path) {
        try {
            $Json = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable
            foreach ($Pair in $Json.expansions.GetEnumerator()) {
                $Map[[CIPP.DocsIndex]::Stem(([string]$Pair.Key).ToLowerInvariant())] = @($Pair.Value)
            }
        } catch {
            Write-Information "[MCP] DocsSynonyms.json could not be read, continuing without query expansion: $($_.Exception.Message)"
        }
    }

    $script:CippDocSynonym = $Map
    return $Map
}

function Get-CippDoc {
    <#
    .SYNOPSIS
        Returns the full text of one documentation page.
    .DESCRIPTION
        Backs the GetDoc core tool, for when a SearchDocs excerpt is not enough. Accepts whatever
        identifier the caller happens to be holding - the repo-relative path from a search result,
        the published slug, or the CIPP route the page documents - because an agent that found a
        page one way should not have to convert it to another. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $null = Get-CippDocsIndex

    $Page = [CIPP.DocsIndex]::FindPage($Path)
    if (-not $Page) {
        # Deduplicated by page: a search returns up to two sections per page, and offering the
        # same path twice as a 'did you mean' just wastes one of three suggestions.
        $Near = @((Find-CippDoc -Query ($Path -replace '[/\-_.]', ' ') -Limit 6).results |
                ForEach-Object { $_.path } | Select-Object -Unique | Select-Object -First 3)
        return [ordered]@{
            error       = "No documentation page matches '$Path'."
            suggestions = @($Near)
            hint        = 'Find a page with SearchDocs first; its "path" is what this tool takes.'
        }
    }

    $Result = [ordered]@{
        title       = $Page.Title
        description = $Page.Description
        path        = $Page.RelativePath
        breadcrumb  = $Page.Breadcrumb
        docsUrl     = $Page.DocsUrl
        githubUrl   = $Page.GitHubUrl
    }
    if ($Page.AppPath) { $Result['appPath'] = $Page.AppPath }
    if (-not $Page.Published) {
        $Result['note'] = 'Not published on docs.cipp.app; use the GitHub link.'
    }
    $Result['sections'] = @($Page.Headings)
    $Result['content'] = [CIPP.DocsIndex]::GetPageText($Page.RelativePath)

    return $Result
}
