function New-CippExtensionUiSection {
    <#
        .SYNOPSIS
        A sub-section inside a card: a small heading with an optional count, then already-rendered HTML.
    #>
    param([string]$Title, [string]$Count, [Parameter(Mandatory)][string]$Body, [string]$Style = 'border-top:1px solid rgba(128,128,128,.2);padding:10px 0')
    $Cnt = if ($Count) { ' ' + (New-CippExtensionUiChip -Text $Count -Small -Strong) } else { '' }
    "<div style=`"$Style`"><div style=`"font-size:13px;font-weight:500`">$(ConvertTo-CippExtensionUiText $Title)$Cnt</div>$Body</div>"
}
