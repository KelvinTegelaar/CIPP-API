function Set-CIPPBaselineTrendPoint {
    <#
    .SYNOPSIS
        Upserts today's compliance rollups into the BaselineTrend table.
    .DESCRIPTION
        One row per UTC day per bucket, written after every orchestrated baseline run
        finishes - later runs the same day overwrite the day's point with the newer state.
        Buckets: 'fleet' (the Fleet Overview trend chart), 'tenant_<domain>' (the tenant
        view's trend chart) and 'standard_<instance>' (the standard offcanvas trend chart;
        '#' sanitized to '~' - forbidden in Azure Table keys). All three come from the one
        resolved-store read, so per-tenant and per-standard points cost nothing extra.
        RowKey is yyyy-MM-dd so every partition sorts chronologically. Buckets mirror the
        scoring in Get-CIPPBaselineAlignment: aligned = Compliant + Accepted, verified =
        Compliant only, drift includes Partially Accepted, and License Missing / No Data
        rows are excluded from the applicable base.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
    $Rows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey ne ''")
    if ($Rows.Count -eq 0) { return }

    $Day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $TrendTable = Get-CippTable -tablename 'BaselineTrend'
    $TrendTable.Force = $true

    $WritePoint = {
        param($PartitionKey, $BucketRows)
        $BucketRows = @($BucketRows)
        $Total = $BucketRows.Count
        $LicenseMissing = @($BucketRows | Where-Object { $_.Status -eq 'Skipped - No License' }).Count
        $NoData = @($BucketRows | Where-Object { $_.Status -eq 'No Data' }).Count
        $Applicable = $Total - $LicenseMissing - $NoData
        $Compliant = @($BucketRows | Where-Object { $_.Status -eq 'Compliant' }).Count
        $Accepted = @($BucketRows | Where-Object { $_.Status -eq 'Accepted' }).Count
        $Drift = @($BucketRows | Where-Object { $_.Status -in @('Drift', 'Partially Accepted') }).Count
        $Denied = @($BucketRows | Where-Object { $_.Status -like 'Denied - *' }).Count
        $Pct = { param($Count) if ($Applicable) { [math]::Round(($Count / $Applicable) * 100) } else { 0 } }

        Add-CIPPAzDataTableEntity @TrendTable -Entity @{
            PartitionKey   = "$PartitionKey"
            RowKey         = $Day
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

    & $WritePoint 'fleet' $Rows
    foreach ($Group in ($Rows | Group-Object -Property PartitionKey)) {
        & $WritePoint ('tenant_{0}' -f $Group.Name) $Group.Group
    }
    foreach ($Group in ($Rows | Group-Object -Property StandardName)) {
        if (-not $Group.Name) { continue }
        & $WritePoint ('standard_{0}' -f ($Group.Name -replace '#', '~')) $Group.Group
    }
}
