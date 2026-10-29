function Get-CippExtensionUiTone {
    <#
        .SYNOPSIS
        Fill, border and bar colours for a status tone.

        .DESCRIPTION
        Fills and borders are translucent so the same output reads on Hudu's light and dark themes.
    #>
    param([string]$Tone = 'neutral')
    switch ($Tone) {
        'ok' { @{ Bg = 'rgba(16,185,129,.16)'; Bd = 'rgba(16,185,129,.55)'; Bar = '#10B981' } }
        'warn' { @{ Bg = 'rgba(247,144,9,.16)'; Bd = 'rgba(247,144,9,.6)'; Bar = '#F79009' } }
        'err' { @{ Bg = 'rgba(240,68,56,.16)'; Bd = 'rgba(240,68,56,.6)'; Bar = '#F04438' } }
        'info' { @{ Bg = 'rgba(6,174,212,.16)'; Bd = 'rgba(6,174,212,.6)'; Bar = '#06AED4' } }
        'cipp' { @{ Bg = 'rgba(247,127,0,.10)'; Bd = 'rgba(247,127,0,.7)'; Bar = '#F77F00' } }
        default { @{ Bg = 'rgba(128,128,128,.12)'; Bd = 'rgba(128,128,128,.35)'; Bar = '#8a8f98' } }
    }
}
