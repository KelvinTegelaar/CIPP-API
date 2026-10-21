function Get-HuduUiIcon {
    <#
        .SYNOPSIS
        Returns the markup for an icon.

        .DESCRIPTION
        Hudu strips inline SVG from rich text but loads Font Awesome, so icons are Font Awesome classes.
        Name is one of the named icons below or a Font Awesome solid icon name such as envelope.

        .PARAMETER Badge
        Draws the icon in brand orange on a 24px rounded square, inline-block so following text keeps its place when the icon is blank.
    #>
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Name, [switch]$Badge)
    if ($Badge) {
        return "<span style=`"display:inline-block;vertical-align:middle;width:24px;height:24px;line-height:24px;text-align:center;border-radius:6px;background:rgba(247,127,0,.12);margin-right:8px`"><i class=`"fas fa-$($Name.ToLowerInvariant())`" style=`"color:#f77f00;font-size:12px`"></i></span>"
    }
    switch ($Name) {
        'External' { '<i class="fas fa-external-link-alt" style="opacity:.6;font-size:11px;margin-left:6px"></i>' }
        'Warning' { '<i class="fas fa-exclamation-triangle" style="margin-right:8px"></i>' }
        'ServicePrincipal' { '<i class="fas fa-robot" title="Service principal" style="opacity:.75;margin-right:5px"></i>' }
        'User' { '<i class="fas fa-user" title="User" style="opacity:.75;margin-right:5px"></i>' }
        'Group' { '<i class="fas fa-users" title="Group" style="opacity:.75;margin-right:5px"></i>' }
        default { "<i class=`"fas fa-$($Name.ToLowerInvariant())`" style=`"margin-right:6px`"></i>" }
    }
}
