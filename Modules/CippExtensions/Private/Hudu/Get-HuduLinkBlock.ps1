function Get-HuduLinkBlock($URL, $Icon, $Title) {
    # Background and text colour are set together on the same element with fixed values.
    # Hudu does not define the --primary CSS variable in either theme, so the previous button
    # background never rendered and the hard-coded white link text was invisible in light mode.
    $Style = 'display: inline-block; margin: 0 .25rem .25rem 0; padding: .375rem .75rem; border-radius: .25rem; background-color: #1f6feb; color: #ffffff; text-decoration: none; white-space: nowrap;'
    return '<a class="button" role="button" style="{0}" href="{1}" target="_blank"><i class="{2} me-2"></i>{3}</a>' -f $Style, $URL, $Icon, $Title
}
