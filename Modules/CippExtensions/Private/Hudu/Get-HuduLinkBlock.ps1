function Get-HuduLinkBlock($URL, $Icon, $Title) {
    return "<div class='o365__app' style='text-align:center'><a href=$URL target=_blank><h3><i class=`"$Icon`">&nbsp;&nbsp;&nbsp;</i>$Title</h3></a></div>"
}
