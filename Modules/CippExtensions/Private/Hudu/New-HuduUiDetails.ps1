function New-HuduUiDetails {
    <#
        .SYNOPSIS
        A collapsed section. Hudu's editor keeps <details class="mce-accordion"> editable and collapsible.

        .PARAMETER Icon
        A Font Awesome solid icon name shown as a brand badge before the summary.

        .PARAMETER Body
        Already-rendered HTML.
    #>
    param([string]$Summary, [string]$Count, [Parameter(Mandatory)][string]$Body, [string]$Style = 'border-top:1px solid rgba(128,128,128,.2);padding:10px 0', [string]$Icon)
    $Cnt = if ($Count) { " <span style=`"font-weight:400;opacity:.65`">$(ConvertTo-HuduUiText $Count)</span>" } else { '' }
    "<details class=`"mce-accordion`" style=`"$Style`"><summary style=`"cursor:pointer;font-size:13px;font-weight:500`">$(if ($Icon) { Get-HuduUiIcon -Name $Icon -Badge })<span style=`"vertical-align:middle`">$(ConvertTo-HuduUiText $Summary)$Cnt</span></summary>$Body</details>"
}
