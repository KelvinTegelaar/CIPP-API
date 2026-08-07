function ConvertTo-CippMarkdownCell {
    <#
    .SYNOPSIS
        Escapes a value so it is safe to interpolate into a Markdown table cell.

    .DESCRIPTION
        Tenant data routinely contains pipes - display names in the form 'John Doe | Contoso'
        are a common MSP convention. Dropped straight into a table row, every pipe opens a new
        column, so the value splits across cells and each one after it lands under the wrong
        header. Escaping them as \| keeps the row exactly as wide as the header declares.

        Newlines get the same treatment. A Markdown table row is line-based, so an embedded
        newline turns one row into two malformed ones; they are collapsed to spaces instead.

    .PARAMETER Value
        The value to escape. Non-string input is converted with ToString(); $null becomes ''.

    .EXAMPLE
        ConvertTo-CippMarkdownCell -Value 'John Doe | Contoso'

        Returns 'John Doe \| Contoso'.

    .EXAMPLE
        $Users | ForEach-Object { "| $(ConvertTo-CippMarkdownCell $_.displayName) | $($_.id) |" }

        Builds table rows whose columns survive display names containing pipes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        $Value
    )

    process {
        if ($null -eq $Value) { return '' }

        $Text = [string]$Value
        if ([string]::IsNullOrEmpty($Text)) { return '' }

        return ($Text -replace '\|', '\|' -replace '\r?\n', ' ').Trim()
    }
}
