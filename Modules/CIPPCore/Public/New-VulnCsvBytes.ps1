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

    $Sb = [System.Text.StringBuilder]::new()
    [void]$Sb.AppendLine(($Headers -join ','))

    foreach ($Row in $Rows) {
        $Cells = foreach ($Header in $Headers) {
            $Val = $Row.$Header
            if ($null -ne $Val) {
                $S = [string]$Val
                if ($S -match '[,"\r\n]') { '"' + ($S -replace '"', '""') + '"' } else { $S }
            } else { '' }
        }
        [void]$Sb.AppendLine(($Cells -join ','))
    }

    return [System.Text.Encoding]::UTF8.GetBytes($Sb.ToString())
}
