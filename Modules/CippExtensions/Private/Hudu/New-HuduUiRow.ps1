function New-HuduUiRow {
    <#
        .SYNOPSIS
        A label/value table row: label on the left, value on the right. An empty value renders a muted "Not set"; a long value wraps inside its cell.

        .DESCRIPTION
        Emits a bare <tr>; New-HuduUiCard wraps each run of consecutive rows in one table.
    #>
    param([string]$Label, [AllowNull()][string]$Value, [string]$Note)
    $S = Get-HuduUiTableStyle
    $V = if ([string]::IsNullOrWhiteSpace($Value)) { '<span style="opacity:.55">Not set</span>' } else { ConvertTo-HuduUiText $Value }
    $N = if ($Note) { " <span style=`"opacity:.65`">($(ConvertTo-HuduUiText $Note))</span>" } else { '' }
    "<tr><td style=`"$($S.RowLabel);$($S.RowSep)`">$(ConvertTo-HuduUiText $Label)</td><td style=`"$($S.RowValue);$($S.RowSep)`">$V$N</td></tr>"
}
