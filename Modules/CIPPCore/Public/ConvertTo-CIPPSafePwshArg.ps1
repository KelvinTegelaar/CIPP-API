function ConvertTo-CIPPSafePwshArg {
    <#
    .SYNOPSIS
        Escapes a value for safe use as a single PowerShell command-line argument.
    .DESCRIPTION
        Wraps values in single quotes and escapes embedded single quotes by doubling them.
        Also strips CR/LF to prevent multiline argument injection when command lines are
        generated as strings for downstream execution (for example, Intune install commands).
    .PARAMETER Value
        The value to encode as a PowerShell-safe argument token.
    .EXAMPLE
        $SafeValue = ConvertTo-CIPPSafePwshArg -Value $Request.Body.customArguments
        $Command = "powershell.exe -ExecutionPolicy Bypass .\\install.ps1 -CustomArguments $SafeValue"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    $EscapedValue = $Value -replace "'", "''"
    $EscapedValue = $EscapedValue -replace "`r|`n", ' '

    return "'{0}'" -f $EscapedValue
}
