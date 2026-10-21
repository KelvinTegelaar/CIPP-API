function New-HuduUiLink {
    <#
        .SYNOPSIS
        A link opening in a new tab. Url, label and tip are encoded here.

        .DESCRIPTION
        Only http and https URLs become links; anything else renders as the plain label. Buttons are inline-block;
        callers put a space between adjacent buttons because Hudu's mobile app drops their margins.

        .PARAMETER Variant
        button: outlined Microsoft/PSA button. cipp: orange CIPP button. strong: bold underlined inline link. text: underlined inline link.
    #>
    param(
        [string]$Url, [string]$Label, [string]$Tip,
        [ValidateSet('button', 'cipp', 'strong', 'text')][string]$Variant = 'button'
    )
    if ($Url -notmatch '^https?://') { return "<span>$(ConvertTo-HuduUiText $Label)</span>" }
    $Common = "href=`"$(ConvertTo-HuduUiText $Url)`" target=`"_blank`" rel=`"noopener noreferrer nofollow`" title=`"$(ConvertTo-HuduUiText $Tip)`""
    $Underline = 'color:inherit;text-decoration:underline;text-decoration-color:rgba(247,127,0,.7);text-underline-offset:3px'
    $Button = 'display:inline-block;vertical-align:middle;margin:0 6px 6px 0;padding:4px 7px;border-radius:6px;font-size:13px;font-weight:500;color:inherit;text-decoration:none;line-height:20px'
    switch ($Variant) {
        'button' { "<a $Common style=`"$Button;border:1px solid rgba(128,128,128,.45)`">$(ConvertTo-HuduUiText $Label)$(Get-HuduUiIcon -Name External)</a>" }
        'cipp' { "<a $Common style=`"$Button;border:1px solid rgba(247,127,0,.7);background:rgba(247,127,0,.1)`">$(ConvertTo-HuduUiText $Label)</a>" }
        'strong' { "<a $Common style=`"font-weight:600;$Underline`">$(ConvertTo-HuduUiText $Label)</a>" }
        'text' { "<a $Common style=`"$Underline`">$(ConvertTo-HuduUiText $Label)</a>" }
    }
}
