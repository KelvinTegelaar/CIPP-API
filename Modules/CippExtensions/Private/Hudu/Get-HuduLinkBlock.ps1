function Get-HuduLinkBlock($URL, $Icon, $Title) {
    return "<button class='button' style='background-color: var(--primary)' role='button'><a style='color: white;' role='button' href=$URL target=_blank><i class=`"$Icon me-2`" />$Title</a></button>"
}
