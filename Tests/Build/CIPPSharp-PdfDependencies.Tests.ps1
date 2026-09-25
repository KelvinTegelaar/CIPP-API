# Guards the bundling of the server-side PDF renderer: the OfficeIMO DLLs must ship next to
# CIPPSharp.dll (loaded via RequiredAssemblies; .NET resolves them by same-directory probing, there
# is no deps.json), and the CIPPSharp assembly must expose the ReportPdf entry point.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
}

Describe 'CIPPSharp PDF dependencies' {
    It 'ships CIPPSharp.dll' {
        Test-Path (Join-Path $script:Bin 'CIPPSharp.dll') | Should -BeTrue
    }
    It 'ships OfficeIMO.Pdf.dll beside CIPPSharp.dll' {
        Test-Path (Join-Path $script:Bin 'OfficeIMO.Pdf.dll') | Should -BeTrue
    }
    It 'ships OfficeIMO.Core.dll beside CIPPSharp.dll' {
        Test-Path (Join-Path $script:Bin 'OfficeIMO.Core.dll') | Should -BeTrue
    }
    It 'does not ship the System.Management.Automation facade' {
        Test-Path (Join-Path $script:Bin 'System.Management.Automation.dll') | Should -BeFalse
    }
    It 'ships the emoji fallback font beside CIPPSharp.dll' {
        # The monochrome symbol/emoji fallback the renderer loads at runtime (ReportPdf.EmojiFontBytes);
        # without it emoji degrade to ASCII tokens rather than glyphs.
        Test-Path (Join-Path $script:Bin 'emoji-fallback.ttf') | Should -BeTrue
    }
    It 'ships the Twemoji colour emoji image set' {
        # The colour emoji PNGs the renderer places inline (TwemojiAssets); a large individual-file set so a
        # render only reads the handful it embeds. A few thousand files, keyed by lowercase hex code point.
        $twemoji = Join-Path $script:Bin 'twemoji'
        Test-Path $twemoji | Should -BeTrue
        (Get-ChildItem -Path $twemoji -Filter '*.png' -File).Count | Should -BeGreaterThan 1000
        Test-Path (Join-Path $twemoji '26a0.png') | Should -BeTrue   # warning
        Test-Path (Join-Path $twemoji '2705.png') | Should -BeTrue   # green check
    }
    It 'exposes the ReportPdf renderer type' {
        [void][System.Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'OfficeIMO.Core.dll'))
        [void][System.Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'OfficeIMO.Pdf.dll'))
        [void][System.Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'CIPPSharp.dll'))
        ([type]'CIPP.Reporting.ReportPdf') | Should -Not -BeNullOrEmpty
    }
}
