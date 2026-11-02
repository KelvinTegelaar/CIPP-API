function ConvertTo-CippExtensionNinjaOneHtml {
    <#
        .SYNOPSIS
        Adapts documentation kit HTML to the NinjaOne WYSIWYG field.

        .DESCRIPTION
        NinjaOne paints its own cell grid and drops backgrounds, opacity and border-top: cells get padding on every
        side, toned chips keep their colour as text colour, and accents move to the left edge.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Html)
    $Html = [regex]::Replace($Html, '<t[dh] style="[^"]*"', {
            param($Cell)
            $Cell.Value -replace 'padding:(?:7px 12px 7px 0|7px 0|8px|6px 8px)(?=;|")', 'padding:7px 10px' -replace ';padding-(?:left|right):0(?=;|")', ''
        })
    $Html = $Html.Replace('border:1px solid rgba(247,144,9,.5)"', 'border:1px solid rgba(247,144,9,.5);border-left:4px solid #F79009"')
    $Html = $Html.Replace('border-top:3px solid #f77f00', 'border-left:3px solid #f77f00')
    [regex]::Replace($Html, 'background:rgba\((\d+,\d+,\d+),[.\d]+\);border:1px solid rgba\(\1,[.\d]+\)(?=")', {
            param($Chip)
            if ($Chip.Groups[1].Value -eq '128,128,128') { $Chip.Value } else { "$($Chip.Value);color:rgb($($Chip.Groups[1].Value))" }
        })
}
