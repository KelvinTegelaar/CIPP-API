function New-HuduUiCard {
    <#
        .SYNOPSIS
        A bordered card with a heading, an optional count and an optional note or flag after the title.

        .DESCRIPTION
        Hudu's mobile app ignores flex, so the heading is inline flow and the note wraps under the title when it does not fit.

        .PARAMETER Body
        Already-rendered HTML. Each run of top-level <tr> rows (New-HuduUiRow) is wrapped in one table.

        .PARAMETER Icon
        A Font Awesome solid icon name shown as a brand badge before the title.

        .PARAMETER Flag
        Already-rendered HTML shown after the title when there is no Right text.
    #>
    param(
        [string]$Title, [string]$Count, [string]$Right, [Parameter(Mandatory)][string]$Body,
        [string]$Flag, [string]$Icon, [switch]$Spaced, [int]$HeadingGap = 8
    )
    # Hudu's web app wraps every table in a padded scroll div, so each run of rows shares one table
    $Row = (Get-HuduUiTableStyle).Row
    $Body = [regex]::Replace($Body, '(?s)(?<!<tbody>|</tr>)<tr>.*?</tr>(?!<tr>)', { param($r) "<table style=`"$Row`"><tbody>$($r.Value)</tbody></table>" })
    $Margin = if ($Spaced) { ';margin-top:12px' } else { '' }
    $Cnt = if ($Count) { ' ' + (New-HuduUiChip -Text $Count -Small -Strong) } else { '' }
    $Badge = if ($Icon) { Get-HuduUiIcon -Name $Icon -Badge } else { '' }
    $Text = "<span style=`"vertical-align:middle`">$(ConvertTo-HuduUiText $Title)$Cnt</span>"
    $RightHtml = if ($Right) { "<span style=`"display:inline-block;vertical-align:middle;font-size:12px;opacity:.7`">$(ConvertTo-HuduUiText $Right)</span>" } else { $Flag }
    $Head = if ($RightHtml) {
        "<div style=`"margin:0 0 $($HeadingGap)px`"><h3 style=`"display:inline-block;vertical-align:middle;margin:0 8px 0 0;font-size:15px;font-weight:600;line-height:1.4`">$Badge$Text</h3> $RightHtml</div>"
    } else {
        "<h3 style=`"margin:0 0 $($HeadingGap)px;font-size:15px;font-weight:600;line-height:1.4`">$Badge$Text</h3>"
    }
    "<div style=`"border:1px solid rgba(128,128,128,.3);border-radius:6px;padding:14px 16px;box-sizing:border-box$Margin`">$Head$Body</div>"
}
