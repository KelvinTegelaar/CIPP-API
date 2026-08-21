function Test-CIPPHtmlIsEmpty {
    <#
    .SYNOPSIS
        Returns true when HTML from a rich-text editor has no meaningful content.
    .DESCRIPTION
        TipTap and similar editors persist empty documents as placeholder markup such as
        <p></p> or <p><br></p>. Treat those the same as a blank string so callers do not
        act on "empty" Out of Office messages.
    .PARAMETER Html
        The HTML string to inspect.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Html
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return $true
    }

    $Plain = $Html -replace '(?i)<br\s*/?>', ' ' -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '\s+', ''
    return [string]::IsNullOrEmpty($Plain)
}
