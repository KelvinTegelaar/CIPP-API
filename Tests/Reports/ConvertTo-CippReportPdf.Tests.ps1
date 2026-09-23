# Pester tests for ConvertTo-CippReportPdf and the CIPPSharp component kit it wraps.
# Verifies every block type renders to a valid PDF, empty input still produces a page, branding is
# applied without throwing, and every image format the engine accepts decodes and renders.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    $HelperPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CippReportPdf.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $HelperPath) { throw 'Could not locate ConvertTo-CippReportPdf.ps1 under Modules/' }
    . $HelperPath
    # The wrapper resolves branding itself when none is passed; keep that offline.
    function Get-CIPPBrandingSettings { @{} }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }

    function Test-IsPdf {
        param($Bytes)
        if ($Bytes -isnot [byte[]] -or $Bytes.Length -lt 100) { return $false }
        return ([System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) -eq '%PDF-')
    }

    # 1x1 transparent PNG.
    $script:TinyPng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
}

Describe 'ConvertTo-CippReportPdf' {
    Context 'Block types render to a valid PDF' {
        It 'renders a blank (HTML) block with marks and a list' {
            $b = @(@{ type = 'blank'; title = 'Summary'; content = '<p>Hello <strong>world</strong> and <em>more</em></p><ul><li>one</li><li>two</li></ul>' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -TenantName 'Contoso' -ReportName 'T') | Should -BeTrue
        }
        It 'renders a markdown test block with a status and a table' {
            $md = "## Details`n`nUsers without **MFA** are exposed. SKU ``SPE_E5`` stays literal.`n`n| Setting | State |`n|---|---|`n| MFA | Off |"
            $b = @(@{ type = 'test'; title = 'MFA'; status = 'Failed'; static = $false; content = $md })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a database markdown table block' {
            $b = @(@{ type = 'database'; title = 'Users'; format = 'text'; content = "| Name | UPN |`n|---|---|`n| Bob | bob@x.com |" })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a database csv/json block as a code block' {
            $b = @(@{ type = 'database'; title = 'Raw'; format = 'json'; content = '[{"a":1}]' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a scorecard block' {
            $b = @(@{ type = 'scorecard'; title = 'At a glance'; stats = @(@{ value = '3'; label = 'Anon' }, @{ value = '7'; label = 'No expiry' }) })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a chart block' {
            $b = @(@{ type = 'chart'; title = 'By risk'; chartData = @(@{ label = 'High'; value = 5 }, @{ label = 'Low'; value = 9 }) })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a hero and a page break without throwing' {
            $b = @(@{ type = 'hero'; title = 'Chapter'; heroHighlight = '39' }, @{ type = 'pagebreak' }, @{ type = 'blank'; content = '<p>after</p>' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
    }

    Context 'Edge cases' {
        It 'renders an empty component tree as a valid one-page PDF' {
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks @()) | Should -BeTrue
        }
        It 'applies a branding colour without throwing' {
            $b = @(@{ type = 'blank'; content = '<p>x</p>' })
            $branding = @{ colour = '#0E4C92'; secondaryColour = '#F77F00'; watermarkText = 'DRAFT'; watermarkEnabled = $true; footerText = '%tenantname% report' }
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -Branding $branding -TenantName 'Contoso') | Should -BeTrue
        }
        It 'still renders when the branding logo cannot be embedded (skips it gracefully)' {
            $b = @(@{ type = 'blank'; content = '<p>x</p>' })
            # An unusable logo (here a PNG OfficeIMO rejects) must not sink the whole report.
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -Branding @{ logo = $script:TinyPng }) | Should -BeTrue
        }
        It 'renders a table row taller than a page (the keep-rows-whole guard lets it split, not throw)' {
            # Rich table rows are kept whole like the client's wrap={false}; OfficeIMO throws on an
            # unsplittable row taller than the page, so a row this tall must stay splittable.
            $Tall = (1..150 | ForEach-Object { "Line $_ of a very tall cell" }) -join "`n"
            $Cols = @(@{ header = 'Setting'; key = 'name'; width = 1 }, @{ header = 'Value'; key = 'value'; width = 2 })
            $Rows = @(@{ name = 'Short'; value = 'x' }, @{ name = 'Tall'; value = $Tall }, @{ name = 'After'; value = 'y' })
            $b = @(@{ type = 'richtable'; title = 'Tall'; columns = $Cols; rows = $Rows; limit = 10 })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'moves a row that would straddle a page break whole onto the next page' {
            # Twenty short lines in a third-width column: about 220pt, under half a page, so it is kept
            # whole. Filler rows put its top near the page foot, where it would otherwise be cut (a
            # row follows it: OfficeIMO already moves a table's last row whole).
            $Tall = (@('ROWSTART') + (2..19 | ForEach-Object { "Line $_ of the setting value" }) + @('ROWEND')) -join "`n"
            $Cols = @(@{ header = 'Setting'; key = 'name'; width = 1 }, @{ header = 'Today'; key = 'value'; width = 1 }, @{ header = 'Target'; key = 'target'; width = 1 })
            $Rows = @(1..20 | ForEach-Object { @{ name = "Filler $_"; value = 'x'; target = 'y' } }) +
                @(@{ name = 'Tall'; value = $Tall; target = 'z' }, @{ name = 'After'; value = 'x'; target = 'y' })
            $b = @(@{ type = 'richtable'; title = 'Straddle'; columns = $Cols; rows = $Rows; limit = 50 })
            $Pages = @([OfficeIMO.Pdf.PdfReadDocument]::Open((ConvertTo-CippReportPdf -Blocks $b)).Pages | ForEach-Object { $_.ExtractText() })
            $Start = @(0..($Pages.Count - 1) | Where-Object { $Pages[$_] -match 'ROWSTART' })
            $End = @(0..($Pages.Count - 1) | Where-Object { $Pages[$_] -match 'ROWEND' })
            $Start | Should -HaveCount 1
            $End | Should -Be $Start
        }
        It 'accepts a pre-serialised JSON block string' {
            $json = ConvertTo-Json -InputObject @(@{ type = 'blank'; content = '<p>json</p>' }) -Depth 10
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $json) | Should -BeTrue
        }
    }

    Context 'Image formats' {
        BeforeAll {
            # 1x1 fixtures: the smallest valid GIF and WebP, a two-colour SVG, and a corrupt PNG.
            $script:Gif = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
            $script:Webp = 'data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA'
            $script:Svg = 'data:image/svg+xml;base64,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#F77F00"/></svg>'))
            $script:Block = @(@{ type = 'blank'; title = 'Formats'; content = '<p>x</p>' })
        }
        It 'identifies every raster OfficeIMO decodes, not just PNG and JPEG' {
            [CIPP.Reporting.ReportComponents]::ImageContentType([CIPP.Reporting.ReportComponents]::DecodeImage($script:Gif)) | Should -Be 'image/gif'
            [CIPP.Reporting.ReportComponents]::ImageContentType([CIPP.Reporting.ReportComponents]::DecodeImage($script:Webp)) | Should -Be 'image/webp'
        }
        It 'rasterises an SVG once at decode time so every placement sees a PNG' {
            $bytes = [CIPP.Reporting.ReportComponents]::DecodeImage($script:Svg)
            [CIPP.Reporting.ReportComponents]::ImageContentType($bytes) | Should -Be 'image/png'
            # 40x20 source scaled to 1200px on the long side, aspect kept.
            $size = [CIPP.Reporting.ReportComponents]::ImageSize($bytes)
            $size.Item1 | Should -Be 1200
            $size.Item2 | Should -Be 600
        }
        It 'drops what OfficeIMO cannot identify rather than failing the render' {
            [CIPP.Reporting.ReportComponents]::DecodeImage($script:TinyPng) | Should -BeNullOrEmpty
            [CIPP.Reporting.ReportComponents]::DecodeImage('data:image/png;base64,' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('not an image'))) | Should -BeNullOrEmpty
        }
        It 'renders a GIF logo, an SVG logo and a WebP cover' {
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ logo = $script:Gif }) | Should -BeTrue
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ logo = $script:Svg }) | Should -BeTrue
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ coverImage = $script:Webp; logo = $script:Webp }) | Should -BeTrue
        }
    }

    Context 'Emoji rendering' {
        BeforeAll {
            # A render populates the emoji flags (font coverage from the cmap; Twemoji image assets present).
            $null = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; content = '<p>x</p>' })
        }
        It 'renders arbitrary BMP and astral emoji (incl. a ZWJ sequence) alongside text without throwing' {
            $party = [char]::ConvertFromUtf32(0x1F389)   # astral (surrogate pair)
            $rocket = [char]::ConvertFromUtf32(0x1F680)  # astral
            $star = [char]0x2B50                         # BMP symbol
            $dev = [char]::ConvertFromUtf32(0x1F469) + [char]0x200D + [char]::ConvertFromUtf32(0x1F4BB) # woman technologist (ZWJ)
            $b = @(@{ type = 'blank'; content = "<p>Great work $party a rocket $rocket a star $star a dev $dev and warning [!]</p>" })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders emoji inside a callout (table cell) without throwing' {
            $party = [char]::ConvertFromUtf32(0x1F389)
            $b = @(@{ type = 'infobox'; title = "Alert $party"; tone = 'warn'; content = "Body [!] with a rocket $([char]::ConvertFromUtf32(0x1F680))." })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'loads the bundled monochrome font coverage and the Twemoji image assets' {
            [CIPP.Reporting.ReportMarkdown]::RenderEmojiGlyphs | Should -BeTrue
            [CIPP.Reporting.ReportMarkdown]::EmojiCoverage.Count | Should -BeGreaterThan 100
            [CIPP.Reporting.ReportMarkdown]::RenderEmojiImages | Should -BeTrue
        }
        It 'keeps a colour emoji (which the renderer draws as an image) rather than stripping it' {
            # A red circle has a Twemoji asset, so Sanitize keeps it verbatim for the image renderer.
            [CIPP.Reporting.ReportMarkdown]::Sanitize([char]::ConvertFromUtf32(0x1F534)) | Should -Be ([char]::ConvertFromUtf32(0x1F534))
        }
        It 'promotes the status tokens to their colour glyphs' {
            [CIPP.Reporting.ReportMarkdown]::Sanitize('[Pass]') | Should -Be '✅'
            [CIPP.Reporting.ReportMarkdown]::Sanitize('[Fail]') | Should -Be '❌'
        }
    }
}

Describe 'Watermark layering' {
    # OfficeIMO paints the watermark first; the engine moves its operator block to the end of each page's
    # content stream so it sits over the content, on content pages and dark divider pages alike.
    It 'draws the watermark after everything else on every page that carries one' {
        $Blocks = @(
            @{ type = 'scorecard'; title = 'Figures'; stats = @(@{ value = '1'; label = 'One' }, @{ value = '2'; label = 'Two' }) }
            @{ type = 'hero'; title = 'Divider'; heroHighlight = '83%'; heroSubText = 'of controls in place' }
            @{ type = 'blank'; title = 'After the divider'; content = '<p>Body text under the mark.</p>' }
        )
        $Bytes = ConvertTo-CippReportPdf -Blocks $Blocks -Variables @{} -Branding @{ colour = '#0E4C92'; watermarkText = 'Preview'; watermarkEnabled = $true } -TenantName 'Contoso' -ReportName 'T'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        $Marker = '<50524556494557> Tj'
        $Streams = [regex]::Matches($Pdf, '(?s)<< /Length (\d+) >>\s*stream\n(.*?)\nendstream') | ForEach-Object { $_.Groups[2].Value }
        $Marked = @($Streams | Where-Object { $_.Contains($Marker) })
        # a content page and the divider at least; the cover never carries one
        $Marked.Count | Should -BeGreaterOrEqual 2
        $Streams[0] | Should -Not -Match 'Tj\s*ET\s*Q\s*$'
        foreach ($Data in $Marked) {
            $Data.TrimEnd() | Should -Match "$([regex]::Escape($Marker))\s*ET\s*Q$"
            ([regex]::Matches($Data, '> Tj|\) Tj') | Select-Object -Last 1).Value | Should -Be '> Tj'
            $Data.LastIndexOf(' re') | Should -BeLessThan $Data.IndexOf($Marker)
            # rising left to right like the client's rotate(-45deg), the divider's tag angle written back
            $Data | Should -Match '0\.707 0\.707 -0\.707 0\.707 [\d.]+ [\d.]+ +Tm'
        }
    }

    It 'lifts a mark written with cp1252 characters (curly quote, dash) like any other' {
        $Mark = "O$([char]0x2019)Brien $([char]0x2014) Draft"
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92'; watermarkText = $Mark; watermarkEnabled = $true } -TenantName 'Contoso' -ReportName 'T'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        # WinAnsi: the right single quote is 0x92 and the em dash 0x97
        $Pdf | Should -Match '<4F92425249454E'
        $Streams = [regex]::Matches($Pdf, '(?s)<< /Length (\d+) >>\s*stream\n(.*?)\nendstream') | ForEach-Object { $_.Groups[2].Value }
        $Marked = @($Streams | Where-Object { $_ -match '0\.707 0\.707 -0\.707 0\.707' })
        $Marked.Count | Should -BeGreaterOrEqual 1
        foreach ($Data in $Marked) { $Data.TrimEnd() | Should -Match 'Tj\s*ET\s*Q$' }
    }

    It 'stacks a mark wider than the page on full lines rather than overprinting them' {
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92'; watermarkText = 'Testing watermark'; watermarkEnabled = $true } -TenantName 'Contoso' -ReportName 'T'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        $Hex = { param($s) [Convert]::ToHexString([System.Text.Encoding]::ASCII.GetBytes($s)) }
        # two lines, the second a 1.1x line (79.2pt at 72pt) under the first, not the client's 14pt
        $Pdf | Should -Match ("<{0}> Tj\n-?[\d.]+ -79\.2 Td <{1}> Tj" -f (& $Hex 'TESTING'), (& $Hex 'WATERMARK'))
    }

    It 'prints a mark character outside WinAnsi as ? instead of failing the report' {
        # 'L' with stroke has no WinAnsi code, and the micro sign upper-cases to the Greek capital mu
        $Mark = "$([char]0x0141)$([char]0x00F3)d$([char]0x017A) 5 $([char]0x00B5)m"
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92'; watermarkText = $Mark; watermarkEnabled = $true } -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        [System.Text.Encoding]::Latin1.GetString($Bytes) | Should -Match '0\.707 0\.707 -0\.707 0\.707'
    }

    It 'leaves a document without a watermark untouched' {
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92' } -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        [System.Text.Encoding]::Latin1.GetString($Bytes) | Should -Not -Match '0\.707 0\.707 -0\.707 0\.707'
    }
}

Describe 'Tenant name in the branding text' {
    It 'substitutes %tenantname% with the name the report was given, before the cache-based replacement runs' {
        $script:Seen = @()
        function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $script:Seen += $Text; $Text -replace '%tenantname%', 'CacheName' }
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92'; footerText = 'Prepared for %TenantName%'; watermarkText = '%tenantname%' } -TenantName 'contoso.onmicrosoft.com' -TenantFilter 'contoso.onmicrosoft.com' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        $Branding = $script:Seen | Where-Object { $_ -like '*footerText*' } | Select-Object -First 1
        $Branding | Should -Match 'Prepared for contoso\.onmicrosoft\.com'
        $Branding | Should -Match '"watermarkText":"contoso\.onmicrosoft\.com"'
        $Branding | Should -Not -Match '(?i)%tenantname%'
    }
}

Describe 'Report builder cover block' {
    It 'puts a cover block on the cover and draws nothing else for it' {
        $Bytes = ConvertTo-CippReportPdf -Blocks @(
            @{ type = 'cover'; title = 'Custom Cover'; coverAccent = 'Words'; subtitle = 'A subtitle of my own'; coverLabel = 'My Label' }
            @{ type = 'blank'; title = 'Body'; content = '<p>x</p>' }
        ) -Variables @{} -Branding @{ colour = '#0E4C92' } -TenantName 'Contoso' -ReportName 'Ignored Name'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        $Hex = { param($s) [Convert]::ToHexString([System.Text.Encoding]::ASCII.GetBytes($s)) }
        # the drawing writes a word per string, so the words are what can be matched
        $Pdf | Should -Match (& $Hex 'CUSTOM')
        $Pdf | Should -Match (& $Hex 'COVER')
        $Pdf | Should -Match (& $Hex 'WORDS')
        $Pdf | Should -Match (& $Hex 'LABEL')
        $Pdf | Should -Not -Match (& $Hex 'IGNORED')
        ([regex]::Matches($Pdf, '/Type /Page[^s]')).Count | Should -Be 2
    }
}

Describe 'Cover footer note' {
    It 'prefers the branding cover note over the report''s own, which is the fallback' {
        $Cover = {
            param($Branding)
            $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{ coverfooternote = 'Report wording' } -Branding $Branding -TenantName 'Contoso' -ReportName 'T'
            [OfficeIMO.Pdf.PdfReadDocument]::Open($Bytes).Pages[0].ExtractText()
        }
        $Branded = & $Cover @{ colour = '#0E4C92'; coverFooterText = 'Branded wording' }
        $Branded | Should -Match 'BRANDED\s+WORDING'
        $Branded | Should -Not -Match 'REPORT\s+WORDING'
        & $Cover @{ colour = '#0E4C92' } | Should -Match 'REPORT\s+WORDING'
    }

    It 'keeps the tenant and meta lines on a landscape cover with a logo and a two-line subtitle' {
        # a 3:1 PNG logo: the tallest the cover draws, which leaves a landscape page the least room
        $Logo = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAB4AAAAKCAYAAACjd+4vAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAfSURBVDhPY+DzmfR/IDADugC98KjFdMOjFtMNjzyLAVL6P4McNkyeAAAAAElFTkSuQmCC'
        $Variables = @{ coversubtitle = 'A deliberately long subtitle that wraps onto a second line on the landscape cover of the report'; covermeta = '24 sharing links' }
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables $Variables -Branding @{ colour = '#0E4C92'; logo = $Logo } -TenantName 'Contoso Landscape Tenant' -ReportName 'Quarterly Security Review' -Landscape
        $Cover = [OfficeIMO.Pdf.PdfReadDocument]::Open($Bytes).Pages[0].ExtractText()
        $Cover | Should -Match 'Contoso\s+Landscape\s+Tenant'
        $Cover | Should -Match '24\s+sharing\s+links'
        $Cover | Should -Match 'CONFIDENTIAL'
    }
}

Describe 'Gallery covers on Infographic pages' {
    It 'reads a gallery cover into the page and leaves a missing one as a plain background' {
        function Get-CIPPImage { param($PartitionKey, $Id) if ($Id -eq 'g1') { @{ data = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' } } }
        $Blocks = @(
            @{ type = 'hero'; title = 'With cover'; heroHighlight = '1'; heroImage = 'gallery:g1' }
            @{ type = 'hero'; title = 'Without'; heroHighlight = '2'; heroImage = 'gallery:missing' }
        )
        $Bytes = ConvertTo-CippReportPdf -Blocks $Blocks -Variables @{} -Branding @{ colour = '#0E4C92'; coverStock = 'none' } -TenantName 'Contoso' -ReportName 'T'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        # the PNG carries an alpha mask, so it lands as two image objects; none at all without a cover
        ([regex]::Matches($Pdf, '/Subtype /Image')).Count | Should -BeGreaterOrEqual 1
        $Plain = ConvertTo-CippReportPdf -Blocks @(@{ type = 'hero'; title = 'Without'; heroHighlight = '2'; heroImage = 'gallery:missing' }) -Variables @{} -Branding @{ colour = '#0E4C92'; coverStock = 'none' } -TenantName 'Contoso' -ReportName 'T'
        ([regex]::Matches([System.Text.Encoding]::Latin1.GetString($Plain), '/Subtype /Image')).Count | Should -Be 0
        $Blocks[0].heroImage | Should -BeLike 'data:image/png;base64,*'
        $Blocks[1].heroImage | Should -Be ''
    }
}

Describe 'Table empty state' {
    It 'draws a table''s emptyText inside the table when it has no rows' {
        $Table = @{ type = 'richtable'; columns = @(@{ header = 'Plan'; key = 'p'; width = 2 }, @{ header = 'Seats'; key = 's'; width = 1 }); rows = @(); limit = 10; emptyText = 'Nothing to list.' }
        $Bytes = ConvertTo-CippReportPdf -Blocks @($Table) -Variables @{} -Branding @{ colour = '#0E4C92' } -TenantName 'Contoso' -ReportName 'T'
        $Text = ([OfficeIMO.Pdf.PdfReadDocument]::Open($Bytes).Pages | ForEach-Object { $_.ExtractText() }) -join "`n"
        $Text | Should -Match 'PLAN\s+SEATS\s+Nothing to list\.'
    }

    It 'falls back to the client DataTable''s own wording, and leaves a markdown table without one' {
        $Blocks = @(
            @{ type = 'richtable'; columns = @(@{ header = 'Plan'; key = 'p' }); rows = @(); limit = 10 }
            @{ type = 'database'; title = 'Header only'; format = 'text'; content = "| Name | UPN |`n|---|---|" }
        )
        $Bytes = ConvertTo-CippReportPdf -Blocks $Blocks -Variables @{} -Branding @{ colour = '#0E4C92' } -TenantName 'Contoso' -ReportName 'T'
        $Text = ([OfficeIMO.Pdf.PdfReadDocument]::Open($Bytes).Pages | ForEach-Object { $_.ExtractText() }) -join "`n"
        $Text | Should -Match 'PLAN\s+Nothing to report\.'
        ([regex]::Matches($Text, 'Nothing to report')).Count | Should -Be 1
    }
}
