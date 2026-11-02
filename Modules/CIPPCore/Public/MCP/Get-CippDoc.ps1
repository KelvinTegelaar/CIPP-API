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
