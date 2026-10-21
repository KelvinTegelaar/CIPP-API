function New-HuduUiBar {
    <#
        .SYNOPSIS
        A horizontal usage bar. Pct is an invariant-culture number.

        .DESCRIPTION
        Hudu's mobile app does not paint the fill, so callers show the percentage as text beside or above the bar.

        .PARAMETER Tone
        ok and neutral bars are brand orange; warn, err and info keep their status colour.
    #>
    param([string]$Pct, [string]$Tone = 'ok', [string]$Title, [int]$Height = 8)
    $Color = if ($Tone -in 'ok', 'neutral') { '#f77f00' } else { (Get-HuduUiTone $Tone).Bar }
    $Radius = [int]($Height / 2)
    "<div style=`"height:$($Height)px;border-radius:$($Radius)px;background:rgba(128,128,128,.22);overflow:hidden`" title=`"$(ConvertTo-HuduUiText $Title)`"><div style=`"height:$($Height)px;width:$(ConvertTo-HuduUiText $Pct)%;background:$Color`"></div></div>"
}
