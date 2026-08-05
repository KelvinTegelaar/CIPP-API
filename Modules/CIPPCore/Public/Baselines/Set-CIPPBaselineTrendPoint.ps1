function Set-CIPPBaselineTrendPoint {
    <#
    .SYNOPSIS
        Upserts today's fleet compliance rollup into the BaselineTrend table.
    .DESCRIPTION
        One row per UTC day (PartitionKey 'fleet', RowKey yyyy-MM-dd, so the partition sorts
        chronologically), written after every orchestrated baseline run finishes - later runs
        the same day overwrite the day's point with the newer state. The Fleet Overview trend
        chart reads this partition; before these rollups existed it could only ever show a
        single live point. Buckets mirror the scoring in Get-CIPPBaselineAlignment: aligned =
        Compliant + Accepted, verified = Compliant only, drift includes Partially Accepted,
        and License Missing / No Data rows are excluded from the applicable base.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Rows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey ne ''")
    if ($Rows.Count -eq 0) { return }

    $Total = $Rows.Count
    $LicenseMissing = @($Rows | Where-Object { $_.Status -eq 'Skipped - No License' }).Count
    $NoData = @($Rows | Where-Object { $_.Status -eq 'No Data' }).Count
    $Applicable = $Total - $LicenseMissing - $NoData
    $Compliant = @($Rows | Where-Object { $_.Status -eq 'Compliant' }).Count
    $Accepted = @($Rows | Where-Object { $_.Status -eq 'Accepted' }).Count
    $Drift = @($Rows | Where-Object { $_.Status -in @('Drift', 'Partially Accepted') }).Count
    $Denied = @($Rows | Where-Object { $_.Status -like 'Denied - *' }).Count
    $Pct = { param($Count) if ($Applicable) { [math]::Round(($Count / $Applicable) * 100) } else { 0 } }

    $TrendTable = Get-CippTable -tablename 'BaselineTrend'
    $TrendTable.Force = $true
    Add-CIPPAzDataTableEntity @TrendTable -Entity @{
        PartitionKey   = 'fleet'
        RowKey         = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        Aligned        = [int](& $Pct ($Compliant + $Accepted))
        Verified       = [int](& $Pct $Compliant)
        Compliant      = [int]$Compliant
        Accepted       = [int]$Accepted
        Drift          = [int]$Drift
        Denied         = [int]$Denied
        LicenseMissing = [int]$LicenseMissing
        Total          = [int]$Total
        Applicable     = [int]$Applicable
        CapturedAt     = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    }
}
