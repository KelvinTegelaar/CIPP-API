function New-CippExtensionUiChip {
    <#
        .SYNOPSIS
        A pill with a tone. Text, title and suffix are encoded here.

        .DESCRIPTION
        Inline-block; callers put a space between adjacent chips because Hudu's mobile app drops their margins.
    #>
    param(
        [string]$Text,
        [ValidateSet('neutral', 'ok', 'warn', 'err', 'info', 'cipp')][string]$Tone = 'neutral',
        [string]$Title,
        [switch]$Strong,
        [switch]$Small,
        [string]$Suffix,
        [switch]$NoWrap,
        [ValidateSet('', 'ServicePrincipal', 'User', 'Group')][string]$Icon = ''
    )
    # Hudu strips the CSS gap property, so spacing is done with margins
    $T = Get-CippExtensionUiTone $Tone
    $Weight = if ($Strong) { 'font-weight:500;' } else { '' }
    $Size = if ($Small) { 'padding:0 7px;font-size:11px;line-height:18px' } else { 'padding:1px 9px;font-size:12px;line-height:20px' }
    $Nw = if ($NoWrap) { 'white-space:nowrap;' } else { '' }
    $Tt = if ($Title) { " title=`"$(ConvertTo-CippExtensionUiText $Title)`"" } else { '' }
    $Sx = if ($Suffix) { " <span style=`"opacity:.65;margin-left:2px`">$(ConvertTo-CippExtensionUiText $Suffix)</span>" } else { '' }
    "<span$Tt style=`"display:inline-block;vertical-align:middle;margin:2px 4px 2px 0;$Size;border-radius:6px;$Weight$($Nw)background:$($T.Bg);border:1px solid $($T.Bd)`">$(if ($Icon) { Get-CippExtensionUiIcon -Name $Icon })$(ConvertTo-CippExtensionUiText $Text)$Sx</span>"
}
