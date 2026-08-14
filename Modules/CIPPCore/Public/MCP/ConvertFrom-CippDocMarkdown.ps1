function ConvertFrom-CippDocMarkdown {
    <#
    .SYNOPSIS
        Parses a GitBook markdown page into a title, description and heading-delimited chunks.
    .DESCRIPTION
        Strips the machinery GitBook layers on top of markdown so it does not end up in the search
        index or in a returned snippet: YAML frontmatter (the description is kept), '{% ... %}'
        block tags such as {% stepper %} / {% hint %}, raw <figure>/<img>/<div> embeds, and the
        markdown link/emphasis syntax. Link labels survive because they are real prose; the URLs
        do not, because a query should not match a page on the strength of a href.

        Splits at '##' and '###' headings. Text before the first heading becomes the intro chunk,
        which is what a query about the page as a whole should match. Fenced code blocks are kept
        as text - PowerShell examples in the docs are frequently the thing being searched for - but
        their fence markers and language hints are dropped. Headings inside a fence are ignored, so
        a '# comment' in a shell example does not split the page. Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Markdown,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $Description = ''
    $Body = $Markdown

    # YAML frontmatter, only when it opens the file.
    if ($Body -match '(?s)^﻿?---\r?\n(.*?)\r?\n---\r?\n?(.*)$') {
        $FrontMatter = $Matches[1]
        $Body = $Matches[2]
        if ($FrontMatter -match '(?m)^description:\s*(.+?)\s*$') {
            $Description = $Matches[1].Trim().Trim('"', "'")
        }
    }

    # GitBook block tags: {% stepper %}, {% hint style="info" %}, {% endstep %}, {% include ... %}.
    $Body = $Body -replace '(?s)\{%.*?%\}', ' '
    # Raw HTML embeds - figures, images and the sponsor <div> grids - carry no searchable prose.
    $Body = $Body -replace '(?s)<figure>.*?</figure>', ' '
    $Body = $Body -replace '(?s)<(script|style)\b.*?</\1>', ' '
    $Body = $Body -replace '<[^>]+>', ' '
    # Images before links, so an image's alt text does not survive as if it were a link label.
    $Body = $Body -replace '!\[[^\]]*\]\([^)]*\)', ' '
    $Body = $Body -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $Body = $Body -replace '&nbsp;', ' '

    $Title = ''
    $Chunks = [System.Collections.Generic.List[object]]::new()

    $CurrentHeading = ''
    $CurrentText = [System.Text.StringBuilder]::new()
    $InFence = $false

    $AddChunk = {
        $Text = $CurrentText.ToString()
        $Text = ($Text -replace '[ \t]+', ' ' -replace '(\r?\n\s*){2,}', "`n").Trim()
        if ($Text -or $CurrentHeading) {
            $Chunks.Add([pscustomobject]@{ Heading = $CurrentHeading; Text = $Text })
        }
    }

    foreach ($Line in ($Body -split '\r?\n')) {
        if ($Line -match '^\s*(```|~~~)') {
            $InFence = -not $InFence
            continue
        }

        if (-not $InFence -and $Line -match '^(#{1,6})\s+(.*\S)\s*$') {
            $Level = $Matches[1].Length
            $Text = ($Matches[2] -replace '[`*_~]', '').Trim()

            if ($Level -eq 1 -and -not $Title) {
                # The page's own H1 titles the page; it does not start a chunk.
                $Title = $Text
                continue
            }

            if ($Level -le 3) {
                & $AddChunk
                $CurrentHeading = $Text
                $CurrentText = [System.Text.StringBuilder]::new()
                continue
            }
            # H4+ stays inside the current chunk as ordinary emphasised prose.
            [void]$CurrentText.AppendLine($Text)
            continue
        }

        [void]$CurrentText.AppendLine($Line)
    }
    & $AddChunk

    if (-not $Title) {
        # No H1: fall back to the file (or folder, for a README) name, title-cased.
        $Leaf = [System.IO.Path]::GetFileNameWithoutExtension($RelativePath)
        if ($Leaf -match '(?i)^README$') {
            $Parent = ($RelativePath -replace '\\', '/') -replace '/[^/]+$', ''
            $Leaf = ($Parent -split '/')[-1]
        }
        $Title = (($Leaf -replace '[-_]', ' ') -split ' ' | Where-Object { $_ } | ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
            }) -join ' '
    }

    # Breadcrumb from the folder chain, for display: 'User Documentation > Identity > Users'.
    $Segments = @(($RelativePath -replace '\\', '/') -split '/')
    $Folders = @($Segments | Select-Object -SkipLast 1)
    $Breadcrumb = (@($Folders | ForEach-Object {
                (($_ -replace '[-_]', ' ') -split ' ' | Where-Object { $_ } | ForEach-Object {
                    $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
                }) -join ' '
            }) -join ' > ')

    return [pscustomobject]@{
        Title       = $Title
        Description = $Description
        Breadcrumb  = $Breadcrumb
        Chunks      = $Chunks
    }
}
