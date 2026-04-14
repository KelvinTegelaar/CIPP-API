function New-VulnCsvBytes {
    <#
    .SYNOPSIS
        Build a CSV payload (UTF-8 bytes) from objects with explicit headers.
    .PARAMETER Rows
        Array of PSCustomObject where property names match the provided headers.
    .PARAMETER Headers
        Ordered list of column headers (and property names).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object[]]$Rows = @(),
        [Parameter(Mandatory)][string[]]$Headers
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(($Headers -join ','))

    foreach ($r in $Rows) {
        $cells = foreach ($h in $Headers) {
            $val = $r.$h
            if ($null -ne $val) {
                $s = [string]$val
                if ($s -match '[,"\r\n]') { '"' + ($s -replace '"','""') + '"' } else { $s }
            } else { '' }
        }
        [void]$sb.AppendLine(($cells -join ','))
    }

    return [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
}
