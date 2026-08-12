function ConvertTo-CIPPSharingLinksKeySegment {
    <#
    .SYNOPSIS
        Applies Add-CIPPDbItem's RowKey sanitisation to a single id segment.
    .DESCRIPTION
        Prefix queries against CippReportingDB only match if the prefix is built with the
        exact transformation the rows were written under: path/wildcard chars to '_',
        control chars stripped.
    .FUNCTIONALITY
        Internal
    #>
    param([Parameter(Mandatory = $true)][string]$Value)
    ($Value -replace '[/\\#?]', '_') -replace '[\u0000-\u001F\u007F-\u009F]', ''
}
