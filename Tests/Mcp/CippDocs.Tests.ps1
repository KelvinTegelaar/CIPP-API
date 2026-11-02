# Pester tests for the docs search tools (SearchDocs / GetDoc).
#
# The load-bearing claim these tools make is that every result links somewhere real. A search
# result is only useful if its docs.cipp.app URL resolves, and the URL is derived from the file's
# path rather than looked up - so the derivation is what gets pinned hardest here, against the
# live list of published slugs in Config/DocsPublishedPages.txt. That check caught a rule that is
# not guessable from a path: a folder with no README.md is a grouping folder and GitBook drops it
# from the URL entirely, which silently moved seven pages up a level.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:BackendRoot = $BackendRoot
    $script:RepoRoot = Split-Path -Parent $BackendRoot
    $script:DocsRoot = Join-Path $script:RepoRoot 'docs'

    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    $McpRoot = Join-Path $BackendRoot 'Modules/CIPPCore/Public/MCP'
    foreach ($Leaf in 'Get-CippDocLink.ps1', 'ConvertTo-CippDocToken.ps1', 'ConvertFrom-CippDocMarkdown.ps1',
        'Get-CippDocsIndex.ps1', 'Find-CippDoc.ps1') {
        . (Join-Path $McpRoot $Leaf)
    }

    $env:CIPPRootPath = $BackendRoot

    # Folders owning a README contribute a URL segment; the rest are elided.
    $script:SectionFolder = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Readme in [System.IO.Directory]::EnumerateFiles($script:DocsRoot, 'README.md', [System.IO.SearchOption]::AllDirectories)) {
        $Dir = [System.IO.Path]::GetDirectoryName($Readme)
        if ($Dir.Length -le $script:DocsRoot.Length) { continue }
        $script:SectionFolder.Add(($Dir.Substring($script:DocsRoot.Length).TrimStart('\', '/') -replace '\\', '/')) | Out-Null
    }

    function Resolve-TestLink {
        param([string]$Path, [string]$Heading)
        return Get-CippDocLink -RelativePath $Path -Heading $Heading -SectionFolder $script:SectionFolder
    }
}

Describe 'Get-CippDocAnchor' {

    It 'slugifies a heading the way GitBook does' {
        Get-CippDocAnchor -Heading 'Self-Hosted Deployment' | Should -Be 'self-hosted-deployment'
    }

    It 'deletes apostrophes rather than turning them into separators' {
        # 'you-ve-met' would be a dead anchor on every page with a contraction in a heading.
        Get-CippDocAnchor -Heading "Confirm You've Met All Prerequisites" | Should -Be 'confirm-youve-met-all-prerequisites'
        Get-CippDocAnchor -Heading "Confirm You$([char]0x2019)ve Met All Prerequisites" | Should -Be 'confirm-youve-met-all-prerequisites'
    }

    It 'strips leading hashes and inline markdown' {
        Get-CippDocAnchor -Heading '### Open the **Management** Portal' | Should -Be 'open-the-management-portal'
        Get-CippDocAnchor -Heading 'See [the guide](https://example.com)' | Should -Be 'see-the-guide'
    }

    It 'returns empty for no heading' {
        Get-CippDocAnchor -Heading '' | Should -BeNullOrEmpty
    }
}

Describe 'Get-CippDocLink' {

    It 'maps a page to its published URL and GitHub source' {
        $Link = Resolve-TestLink -Path 'setup/setting-up-cipp/install.md'
        $Link.docsUrl | Should -Be 'https://docs.cipp.app/setup/setting-up-cipp/install'
        $Link.githubUrl | Should -Be 'https://github.com/CyberDrain/CIPP/blob/dev/docs/setup/setting-up-cipp/install.md'
    }

    It 'collapses a README to the folder it indexes' {
        (Resolve-TestLink -Path 'setup/setting-up-cipp/README.md').docsUrl |
            Should -Be 'https://docs.cipp.app/setup/setting-up-cipp'
    }

    It 'publishes the docs root README at /readme' {
        (Resolve-TestLink -Path 'README.md').docsUrl | Should -Be 'https://docs.cipp.app/readme'
    }

    It 'elides a folder that owns no README' {
        # docs/user-documentation/email/resources has no README, so GitBook drops the segment.
        (Resolve-TestLink -Path 'user-documentation/email/resources/management/equipment/edit.md').docsUrl |
            Should -Be 'https://docs.cipp.app/user-documentation/email/management/equipment/edit'
    }

    It 'keeps a top-level folder even though it owns no README' {
        # 'setup' is a SUMMARY.md '## Group', which always contributes its slug.
        $script:SectionFolder.Contains('setup') | Should -BeFalse
        (Resolve-TestLink -Path 'setup/installation/owntenant.md').docsUrl |
            Should -Be 'https://docs.cipp.app/setup/installation/owntenant'
    }

    It 'keeps the real repo path in the GitHub link even when the docs URL elides a folder' {
        $Link = Resolve-TestLink -Path 'user-documentation/email/resources/management/equipment/edit.md'
        $Link.githubUrl | Should -Match 'docs/user-documentation/email/resources/management/equipment/edit\.md$'
    }

    It 'derives the CIPP route for a user-documentation page' {
        (Resolve-TestLink -Path 'user-documentation/identity/administration/users/README.md').appPath |
            Should -Be '/identity/administration/users'
    }

    It 'gives no route to pages that do not document a screen' {
        (Resolve-TestLink -Path 'setup/setting-up-cipp/install.md').appPath | Should -BeNullOrEmpty
    }

    It 'appends the heading anchor to both links' {
        $Link = Resolve-TestLink -Path 'setup/setting-up-cipp/install.md' -Heading 'Self-Hosted Deployment'
        $Link.docsUrl | Should -Be 'https://docs.cipp.app/setup/setting-up-cipp/install#self-hosted-deployment'
        $Link.githubUrl | Should -Match '#self-hosted-deployment$'
    }

    It 'derives a URL matching the live site for every published page' {
        # The whole-corpus check. Config/DocsPublishedPages.txt is a snapshot of docs.cipp.app's
        # own llms.txt index, so a mismatch here means the tool would hand out a URL that 404s.
        $Snapshot = Join-Path $env:CIPPRootPath 'Config/DocsPublishedPages.txt'
        $Snapshot | Should -Exist

        $Published = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Line in (Get-Content $Snapshot)) {
            $Trimmed = $Line.Trim()
            if ($Trimmed -and -not $Trimmed.StartsWith('#')) { $Published.Add($Trimmed) | Out-Null }
        }

        $Generated = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($File in [System.IO.Directory]::EnumerateFiles($script:DocsRoot, '*.md', [System.IO.SearchOption]::AllDirectories)) {
            $Rel = $File.Substring($script:DocsRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            if ($Rel -eq 'SUMMARY.md' -or $Rel -like '.gitbook/*' -or $Rel -like 'legacy-setup-hidden-from-nav/*') { continue }
            $Generated.Add((Resolve-TestLink -Path $Rel).slug) | Out-Null
        }

        $Unreachable = @($Published | Where-Object { -not $Generated.Contains($_) })
        $Unreachable | Should -BeNullOrEmpty -Because "every published page must be reachable from a repo path; missing: $($Unreachable -join ', ')"
    }
}

Describe 'ConvertFrom-CippDocMarkdown' {

    It 'takes the title from the H1 and the description from frontmatter' {
        $Parsed = ConvertFrom-CippDocMarkdown -RelativePath 'a/b.md' -Markdown @'
---
description: Installing Your CIPP
---

# Installation

Intro prose.

## First Section

Body text.
'@
        $Parsed.Title | Should -Be 'Installation'
        $Parsed.Description | Should -Be 'Installing Your CIPP'
        $Parsed.Chunks.Count | Should -Be 2
        $Parsed.Chunks[0].Heading | Should -BeNullOrEmpty
        $Parsed.Chunks[1].Heading | Should -Be 'First Section'
    }

    It 'strips GitBook block tags and HTML embeds' {
        $Parsed = ConvertFrom-CippDocMarkdown -RelativePath 'a/b.md' -Markdown @'
# Page

{% stepper %}
{% step %}
Real content here.
{% endstep %}
{% endstepper %}

<figure><img src="/files/x" alt=""><figcaption></figcaption></figure>
'@
        $Parsed.Chunks[0].Text | Should -Match 'Real content here'
        $Parsed.Chunks[0].Text | Should -Not -Match 'stepper'
        $Parsed.Chunks[0].Text | Should -Not -Match 'figure'
    }

    It 'does not split a page on a comment inside a fenced code block' {
        # A '# Install the module' comment in a PowerShell sample is not a heading.
        $Parsed = ConvertFrom-CippDocMarkdown -RelativePath 'a/b.md' -Markdown @'
# Page

## Real Section

```powershell
# Install the module
Install-Module Foo
```
'@
        @($Parsed.Chunks | Where-Object { $_.Heading }).Count | Should -Be 1
        $Parsed.Chunks[-1].Text | Should -Match 'Install-Module Foo'
    }

    It 'keeps a link label but discards its URL' {
        $Parsed = ConvertFrom-CippDocMarkdown -RelativePath 'a/b.md' -Markdown @'
# Page

See the [Offboarding Wizard](https://example.com/some-unrelated-slug).
'@
        $Parsed.Chunks[0].Text | Should -Match 'Offboarding Wizard'
        $Parsed.Chunks[0].Text | Should -Not -Match 'unrelated-slug'
    }

    It 'falls back to the folder name when a README has no H1' {
        (ConvertFrom-CippDocMarkdown -RelativePath 'user-documentation/gdap-management/README.md' -Markdown 'Just prose.').Title |
            Should -Be 'Gdap Management'
    }
}

Describe 'ConvertTo-CippDocToken' {

    It 'lowercases, drops stop words and stems plurals' {
        ConvertTo-CippDocToken -Text 'The Standards are here' | Should -Be @('standard')
    }

    It 'indexes a compound identifier whole and in parts' {
        $Tokens = ConvertTo-CippDocToken -Text 'ListUsers'
        $Tokens | Should -Contain 'listuser'
        $Tokens | Should -Contain 'list'
        $Tokens | Should -Contain 'user'
    }

    It 'splits a dotted role name without losing the full string' {
        # 'ReadWrite' splits again on the camel-case boundary, so the parts are read + write.
        $Tokens = ConvertTo-CippDocToken -Text 'Identity.User.ReadWrite'
        $Tokens | Should -Contain 'identity.user.readwrite'
        $Tokens | Should -Contain 'identity'
        $Tokens | Should -Contain 'read'
        $Tokens | Should -Contain 'write'
    }

    It 'tokenises a query and the indexed text identically' {
        # If these ever diverge, a term indexed one way is unfindable the other.
        (ConvertTo-CippDocToken -Text 'Conditional Access Policies') |
            Should -Be (ConvertTo-CippDocToken -Text 'conditional access policy')
    }

    It 'returns nothing for empty input' {
        ConvertTo-CippDocToken -Text '' | Should -BeNullOrEmpty
    }
}

Describe 'Get-CippDocsRoot' {

    AfterEach {
        $env:CIPPDocsPath = $null
        $env:CIPPRootPath = $script:BackendRoot
    }

    It 'finds the docs in a source checkout' {
        (Resolve-Path (Get-CippDocsRoot)).Path.TrimEnd('\', '/') |
            Should -Be (Resolve-Path $script:DocsRoot).Path.TrimEnd('\', '/')
    }

    It 'prefers CIPPDocsPath when it is set' {
        $env:CIPPDocsPath = $script:DocsRoot
        Get-CippDocsRoot | Should -Be $script:DocsRoot
    }

    It 'skips a directory that exists but holds no markdown' {
        # Docker leaves exactly this behind: bind-mounting the docs at /app/API/Docs creates an
        # empty backend/Docs on the host, which a bare existence check accepts and then indexes
        # to zero pages - every search silently returns nothing.
        $Empty = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Empty | Out-Null
        try {
            $env:CIPPDocsPath = $Empty
            Get-CippDocsRoot | Should -Not -Be $Empty
            (Resolve-Path (Get-CippDocsRoot)).Path.TrimEnd('\', '/') |
                Should -Be (Resolve-Path $script:DocsRoot).Path.TrimEnd('\', '/')
        } finally {
            Remove-Item -LiteralPath $Empty -Recurse -Force
        }
    }

    It 'returns null when nothing holds documentation' {
        $env:CIPPDocsPath = $null
        $env:CIPPRootPath = [System.IO.Path]::GetTempPath()
        Get-CippDocsRoot | Should -BeNullOrEmpty
    }
}

Describe 'Find-CippDoc' {

    BeforeAll {
        [CIPP.DocsIndex]::Clear()
        $null = Get-CippDocsIndex -DocsRoot $script:DocsRoot -Force
    }

    It 'builds an index over the shipped docs' {
        [CIPP.DocsIndex]::PageCount | Should -BeGreaterThan 300
        [CIPP.DocsIndex]::ChunkCount | Should -BeGreaterThan 1000
    }

    It 'excludes the superseded legacy tree and GitBook includes' {
        $Paths = @([CIPP.DocsIndex]::GetPages() | ForEach-Object { $_.RelativePath })
        @($Paths | Where-Object { $_ -like 'legacy-setup-hidden-from-nav/*' }) | Should -BeNullOrEmpty
        @($Paths | Where-Object { $_ -like '.gitbook/*' }) | Should -BeNullOrEmpty
    }

    It 'withholds a docs URL from pages GitBook does not publish' {
        # These exist in docs/ and in SUMMARY.md but are not live, so linking to them would 404.
        $Unpublished = @([CIPP.DocsIndex]::GetPages() | Where-Object { -not $_.Published })
        $Unpublished.Count | Should -BeGreaterThan 0
        foreach ($Page in $Unpublished) {
            $Page.DocsUrl | Should -BeNullOrEmpty
            $Page.GitHubUrl | Should -Not -BeNullOrEmpty
        }
    }

    It 'finds a page by its own vocabulary' {
        $Result = Find-CippDoc -Query 'offboarding wizard' -Limit 5
        @($Result.results | ForEach-Object { $_.path }) | Should -Contain 'user-documentation/identity/administration/offboarding-wizard.md'
    }

    It 'reaches conditional access from the abbreviation via synonym expansion' {
        # 'CA' appears nowhere in the prose of the pages this has to find.
        $Result = Find-CippDoc -Query 'CA policy' -Limit 5
        @($Result.results | ForEach-Object { $_.title }) -join ' ' | Should -Match 'Conditional Access|CA Polic|CA Template'
    }

    It 'recovers from typos' {
        $Result = Find-CippDoc -Query 'conditonal acces' -Limit 5
        $Result.matchCount | Should -BeGreaterThan 0
        @($Result.results | ForEach-Object { $_.title }) -join ' ' | Should -Match 'Conditional|CA '
    }

    It 'deep-links to the matching section' {
        $Result = Find-CippDoc -Query 'offboarding options' -Limit 5
        $Hit = @($Result.results | Where-Object { $_.section -and $_.docsUrl -match '#' })[0]
        $Hit | Should -Not -BeNullOrEmpty
        $Hit.docsUrl | Should -Match '#'
    }

    It 'looks up documentation by CIPP route' {
        $Result = Find-CippDoc -Path '/identity/administration/users' -Limit 5
        $Result.matchCount | Should -BeGreaterThan 0
        @($Result.results | ForEach-Object { $_.path }) | Should -Contain 'user-documentation/identity/administration/users/README.md'
    }

    It 'scopes a keyword search to a route' {
        $Result = Find-CippDoc -Query 'permissions' -Path '/identity/administration/users' -Limit 5
        $Result.matchCount | Should -BeGreaterThan 0
        foreach ($Hit in $Result.results) {
            $Hit.path | Should -BeLike 'user-documentation/identity/administration/users*'
        }
    }

    It 'does not fill the results with one page' {
        # Without a per-page cap a single long page crowds out every other answer.
        # Grouped through a script block deliberately: results are ordered hashtables, and
        # Group-Object -Property path does not resolve a hashtable key - it silently returns
        # one group of everything, which reads as a failing cap when the cap is fine.
        $Result = Find-CippDoc -Query 'user' -Limit 8
        $Counts = @($Result.results | Group-Object -Property { $_.path } | ForEach-Object { $_.Count })
        ($Counts | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 2
    }

    It 'returns nothing rather than noise for a nonsense query' {
        (Find-CippDoc -Query 'zzzqqqxyz wibblefrotz' -Limit 5).matchCount | Should -Be 0
    }

    It 'asks for input when given neither query nor path' {
        (Find-CippDoc -Limit 5).error | Should -Not -BeNullOrEmpty
    }

    It 'reports an unmatched path instead of silently searching everything' {
        $Result = Find-CippDoc -Path '/no/such/route' -Limit 5
        $Result.matchCount | Should -Be 0
        $Result.hint | Should -Match 'No documentation page matches'
    }

    It 'never returns a result without a usable link' {
        foreach ($Hit in (Find-CippDoc -Query 'standards drift' -Limit 8).results) {
            ($Hit.docsUrl ?? $Hit.githubUrl) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-CippDoc' {

    BeforeAll {
        [CIPP.DocsIndex]::Clear()
        $null = Get-CippDocsIndex -DocsRoot $script:DocsRoot -Force
    }

    It 'accepts a repo path, a published slug or a CIPP route' {
        foreach ($Identifier in 'user-documentation/identity/administration/users/README.md',
            'user-documentation/identity/administration/users',
            '/identity/administration/users') {
            $Doc = Get-CippDoc -Path $Identifier
            $Doc.error | Should -BeNullOrEmpty -Because "'$Identifier' should resolve"
            $Doc.title | Should -Be 'Users'
            $Doc.content | Should -Not -BeNullOrEmpty
        }
    }

    It 'returns the page text with its headings' {
        $Doc = Get-CippDoc -Path 'setup/setting-up-cipp/install.md'
        $Doc.content | Should -Match 'Self-Hosted Deployment'
        $Doc.sections | Should -Contain 'Self-Hosted Deployment'
    }

    It 'suggests alternatives for an unknown page, without repeating one' {
        $Doc = Get-CippDoc -Path 'no/such/page'
        $Doc.error | Should -Not -BeNullOrEmpty
        $Doc.suggestions.Count | Should -Be @($Doc.suggestions | Select-Object -Unique).Count
    }
}

Describe 'MCP gateway exposes the docs tools' {

    BeforeAll {
        $McpRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPCore/Public/MCP'
        . (Join-Path $McpRoot 'Get-CippMcpToolList.ps1')

        function Get-CippMcpToolCatalog { return @() }
    }

    It 'advertises SearchDocs and GetDoc alongside the API gateway tools' {
        $Names = @((Get-CippMcpToolList -Request ([pscustomobject]@{ Query = @{} }) -InformationAction SilentlyContinue) | ForEach-Object { $_.name })
        $Names | Should -Contain 'SearchDocs'
        $Names | Should -Contain 'GetDoc'
        $Names | Should -Contain 'SearchTools'
    }

    It 'gives GetDoc a required path parameter' {
        $Tool = @((Get-CippMcpToolList -Request ([pscustomobject]@{ Query = @{} }) -InformationAction SilentlyContinue) | Where-Object { $_.name -eq 'GetDoc' })[0]
        $Tool.inputSchema.required | Should -Contain 'path'
    }
}
