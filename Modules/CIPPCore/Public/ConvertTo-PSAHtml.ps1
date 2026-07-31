function ConvertTo-PSAHtml {
    <#
    .SYNOPSIS
        Converts alert HTML into a fragment that renders correctly in PSA ticket bodies
    .DESCRIPTION
        Halo stores details_html as-is, but doesn't apply the <style> block when it renders
        the ticket, so class-styled tables come out with no borders or cell padding. Drops
        the style block and moves the styling inline, along with the old border/cellpadding
        attributes, so the markup doesn't depend on a stylesheet being picked up.
    .PARAMETER Html
        The HTML content to convert
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $TableTag = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">'
    $Html = $Html -replace '(?s)<style\b[^>]*>.*?</style>', ''
    $Html = $Html -replace '<table\s+class\s*=\s*"?[\w-]+"?\s*>', $TableTag -replace '<table>', $TableTag
    $Html = $Html -replace '<th>', '<th style="text-align:left;background-color:#f0f0f0;padding:6px 8px;border:1px solid #d0d0d0;">'
    $Html = $Html -replace '<td>', '<td style="padding:6px 8px;border:1px solid #d0d0d0;vertical-align:top;">'
    return $Html
}
