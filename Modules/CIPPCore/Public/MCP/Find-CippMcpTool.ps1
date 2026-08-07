function Find-CippMcpTool {
    <#
    .SYNOPSIS
        Searches and browses the read-only MCP tool catalog without dumping full schemas.
    .DESCRIPTION
        Backs the SearchTools core tool. Three modes, all returning compact, token-cheap results
        (name + category + one-line summary — never inputSchema):
          - No query and no category: an overview of every category with tool counts.
          - Category only: every tool in that category.
          - Query (optionally scoped to a category): keyword search ranked by relevance —
            exact name match, then name hits, then description hits, then category hits.
        Full schemas are fetched per-tool via GetToolInfo. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Request,
        [string]$Query,
        [string]$Category,
        [int]$Limit = 25
    )

    if ($Limit -lt 1) { $Limit = 25 }
    if ($Limit -gt 100) { $Limit = 100 }

    # Dedupe by name: a path exposing both GET and POST projects one catalog entry per method.
    $ByName = [ordered]@{}
    foreach ($Entry in @(Get-CippMcpToolCatalog -Request $Request)) {
        $Name = [string]$Entry.name
        if (-not $ByName.Contains($Name) -or $Entry._method -eq 'POST') { $ByName[$Name] = $Entry }
    }
    $Catalog = @($ByName.Values)

    # Browse mode: no filters at all -> category overview.
    if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($Category)) {
        $Categories = [System.Collections.Generic.List[object]]::new()
        foreach ($Group in ($Catalog | Group-Object -Property { $_._category } | Sort-Object Name)) {
            $Categories.Add([ordered]@{ category = $Group.Name; toolCount = $Group.Count })
        }
        return [ordered]@{
            totalTools = $Catalog.Count
            categories = @($Categories)
            hint       = 'Call SearchTools with a category to list its tools, or with query keywords to search across all tools.'
        }
    }

    $Pool = $Catalog
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $Pool = @($Catalog | Where-Object { [string]$_._category -eq $Category.Trim() })
        if ($Pool.Count -eq 0) {
            return [ordered]@{
                error      = "Unknown category '$Category'."
                categories = @($Catalog | ForEach-Object { [string]$_._category } | Sort-Object -Unique)
            }
        }
    }

    $Tokens = @($Query -split '[^\w]+' | Where-Object { $_ })
    $Scored = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in $Pool) {
        $Score = 0
        if ($Tokens.Count -gt 0) {
            $Name = [string]$Entry.name
            if ($Name -eq $Query.Trim()) { $Score += 200 }
            foreach ($Token in $Tokens) {
                $Pattern = [regex]::Escape($Token)
                if ($Name -match $Pattern) { $Score += 40 }
                elseif ([string]$Entry.description -match $Pattern) { $Score += 10 }
                if ([string]$Entry._category -match $Pattern) { $Score += 5 }
            }
            if ($Score -eq 0) { continue }
        }
        $Scored.Add([pscustomobject]@{ Score = $Score; Entry = $Entry })
    }

    # Ties broken by how much longer the name is than what was asked for, before falling
    # back to alphabetical. Every ListUser* tool scores the same on a name hit, so the
    # alphabetical tiebreak alone answered 'ListUser' with
    # ListUserConditionalAccessPolicies and buried ListUsers - the obvious intent - five
    # places down. The closest-length match is nearly always the one meant.
    $QueryLength = $Query.Trim().Length
    $Ranked = @($Scored | Sort-Object -Property `
        @{ Expression = 'Score'; Descending = $true },
        @{ Expression = { [math]::Abs([string]$_.Entry.name.Length - $QueryLength) }; Descending = $false },
        @{ Expression = { [string]$_.Entry.name }; Descending = $false })

    # Schemas are normally withheld because ~260 of them would flood the caller's context.
    # That reasoning does not hold for a handful of hits: a search narrow enough to return
    # two or three tools has almost certainly found the right one, and making the caller
    # spend a GetToolInfo round trip to learn its arguments is pure latency. Below the
    # threshold the schema comes back with the result and the tool can be run immediately.
    $InlineSchemaThreshold = 3
    $Selected = @($Ranked | Select-Object -First $Limit)
    $IncludeSchema = $Selected.Count -le $InlineSchemaThreshold

    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($Hit in $Selected) {
        $Result = [ordered]@{
            name     = $Hit.Entry.name
            category = $Hit.Entry._category
            summary  = $Hit.Entry._summary
        }
        if ($IncludeSchema) {
            # the full description too - the one-line summary is a truncation of it
            $Result['description'] = $Hit.Entry.description
            $Result['inputSchema'] = $Hit.Entry.inputSchema
        }
        $Results.Add($Result)
    }

    Write-Information "[MCP] SearchTools query='$Query' category='$Category' -> $($Ranked.Count) matches, returning $($Results.Count)"

    # A search that finds nothing is usually a near miss - a singular/plural, a shortened
    # word, or CIPP's own spelling of something ("MailboxCAS" for client access settings).
    # Telling the caller only "no matches" makes it guess again blind, so the closest names
    # are offered instead. Matching on a shortened prefix of each token catches exactly
    # that class: 'mailboxes' still reaches ListMailboxCAS, 'conditional' reaches
    # ListConditionalAccessPolicies.
    $Suggestions = [System.Collections.Generic.List[string]]::new()
    if ($Ranked.Count -eq 0 -and $Tokens.Count -gt 0) {
        foreach ($Length in 6, 5, 4) {
            foreach ($Token in $Tokens) {
                if ($Token.Length -lt $Length) { continue }
                $Stem = [regex]::Escape($Token.Substring(0, $Length))
                foreach ($Entry in $Pool) {
                    if ($Suggestions.Count -ge 5) { break }
                    $Name = [string]$Entry.name
                    if ($Name -match $Stem -and -not $Suggestions.Contains($Name)) { $Suggestions.Add($Name) }
                }
            }
            if ($Suggestions.Count -gt 0) { break }
        }
    }

    $Hint = if ($Results.Count -gt 0 -and $IncludeSchema) {
        'Few enough matches that the input schemas are included - call ExecTool with { name, arguments } to run one. No GetToolInfo needed.'
    } elseif ($Results.Count -gt 0) {
        'Call GetToolInfo with names=[...] to get input schemas, then ExecTool with { name, arguments } to run one.'
    } elseif ($Suggestions.Count -gt 0) {
        'No exact matches. Did you mean one of the tools in suggestions? Search again with one of those names, or call SearchTools with no arguments to browse categories.'
    } else {
        'No matches. Try broader keywords, or call SearchTools with no arguments to browse categories.'
    }

    $Response = [ordered]@{
        matchCount = $Ranked.Count
        tools      = @($Results)
    }
    if ($Suggestions.Count -gt 0) { $Response['suggestions'] = @($Suggestions) }
    $Response['hint'] = $Hint
    return $Response
}
