function Get-HuduUiTableStyle {
    <#
        .SYNOPSIS
        Inline styles for tables, header cells and body cells, and for label/value rows.

        .DESCRIPTION
        Hudu's rich text CSS gives tables a full grid, header fill, margins and (in some versions) fixed layout and nowrap cells; these reset them inline.
        Row is the table New-HuduUiCard wraps label/value rows in; RowCell, RowLabel and RowValue style their cells and RowSep separates them.
    #>
    $Cell = 'border-width:0 0 1px;background:transparent;vertical-align:top'
    $Bare = 'border:0;background:transparent;vertical-align:top'
    @{
        Table    = 'width:100%;border:0;margin:0;table-layout:auto;border-collapse:collapse;font-size:13px'
        Th       = "$Cell;text-align:left;font-weight:500;opacity:.7;padding:6px 8px;border-bottom:1px solid rgba(128,128,128,.35)"
        Td       = "$Cell;padding:8px;border-bottom:1px solid rgba(128,128,128,.2)"
        Row      = 'width:100%;border:0;margin:0;table-layout:auto;border-collapse:collapse;background:transparent;font-size:13px'
        RowCell  = $Bare
        RowLabel = "$Bare;white-space:nowrap;opacity:.7;padding:7px 12px 7px 0"
        RowValue = "$Bare;text-align:right;white-space:normal;word-break:normal;overflow-wrap:anywhere;padding:7px 0"
        RowSep   = 'border-top:1px solid rgba(128,128,128,.2)'
    }
}
