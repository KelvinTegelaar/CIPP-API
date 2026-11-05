function Get-CIPPIntuneReportRows {
    <#
    .SYNOPSIS
        Reads every row of an Intune report action (deviceManagement/reports/get*).
    .DESCRIPTION
        The report actions answer a POST with a column schema plus positional value arrays and page
        with top/skip. This walks the pages and returns one object per row, keyed by column name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$TenantFilter,
        [Parameter(Mandatory)]$Uri,
        $Filter = '',
        $Select = @(),
        $OrderBy = @('PolicyName'),
        [int]$PageSize = 500
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Skip = 0
    do {
        $Body = @{
            top     = $PageSize
            skip    = $Skip
            select  = @($Select)
            orderBy = @($OrderBy)
            search  = ''
            filter  = $Filter
        } | ConvertTo-Json -Compress -Depth 5
        $Page = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -body $Body
        if ($Page -is [string]) { $Page = $Page | ConvertFrom-Json }

        $Columns = @($Page.Schema.Column)
        foreach ($Values in @($Page.Values)) {
            $Row = [ordered]@{}
            for ($Index = 0; $Index -lt $Columns.Count; $Index++) {
                $Row[$Columns[$Index]] = $Values[$Index]
            }
            $Rows.Add([PSCustomObject]$Row)
        }
        $Skip = $Skip + $PageSize
    } while (@($Page.Values).Count -eq $PageSize -and $Skip -lt [int]$Page.TotalRowCount)
    , @($Rows)
}
