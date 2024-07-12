function Get-HuduLinkBlock($URL, $Icon, $Title) {
    return '<button class="button" style="background-color: var(--primary)" role="button"><a style="color: white;" role="button" href="{0}" target="_blank"><i class="{1} me-2"></i>{2}</a></button>' -f $URL, $Icon, $Title
}
