function ConvertTo-CIPPScriptBlockValue {
    <#
    .SYNOPSIS
        Escapes a value for a single-quoted literal inside a script block string.
    .DESCRIPTION
        Doubles every character PowerShell accepts as a single quote (U+0027 and U+2018-U+201B).
        The caller adds the surrounding quotes.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    $Quotes = -join [char[]](0x27, 0x2018, 0x2019, 0x201A, 0x201B)
    return [regex]::Replace([string]$Value, "[$Quotes]", '$0$0')
}
