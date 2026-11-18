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
    $Rows = @(Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey ne ''" -Property PartitionKey, RowKey, StandardName, Status, OriginalEntityId, PartIndex)
    if ($Rows.Count -eq 0) { return }

    $Day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $TrendTable = Get-CippTable -tablename 'BaselineTrend'
    $TrendTable.Force = $true

    # One pass, counts per bucket: [Total, LicenseMissing, NoData, Compliant, Accepted, Drift, Denied].
    # Keys match case-insensitively, like the Group-Object grouping this replaced.
    $Fleet = [int[]]::new(7)
    $ByTenant = [ordered]@{}
    $ByStandard = [ordered]@{}
    foreach ($Row in $Rows) {
        $Slot = switch -Wildcard ($Row.Status) {
            'Skipped - No License' { 1; break }
            'No Data' { 2; break }
            'Compliant' { 3; break }
            'Accepted' { 4; break }
            'Drift' { 5; break }
            'Partially Accepted' { 5; break }
            'Denied - *' { 6; break }
        }
        $TenantKey = "$($Row.PartitionKey)"
        $StandardKey = "$($Row.StandardName)"
        $ByTenant[$TenantKey] ??= [int[]]::new(7)
        $StandardBucket = $null
        if ($StandardKey) {
            $ByStandard[$StandardKey] ??= [int[]]::new(7)
            $StandardBucket = $ByStandard[$StandardKey]
        }
        foreach ($Bucket in $Fleet, $ByTenant[$TenantKey], $StandardBucket) {
            if ($null -eq $Bucket) { continue }
            $Bucket[0]++
            if ($Slot) { $Bucket[$Slot]++ }
        }
    }

    $CapturedAt = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $Points = @(foreach ($Entry in @(
            @{ Key = 'fleet'; Counts = $Fleet }
            foreach ($Key in $ByTenant.Keys) { @{ Key = 'tenant_{0}' -f $Key; Counts = $ByTenant[$Key] } }
            foreach ($Key in $ByStandard.Keys) { @{ Key = 'standard_{0}' -f ($Key -replace '#', '~'); Counts = $ByStandard[$Key] } }
        )) {
        $Total, $LicenseMissing, $NoData, $Compliant, $Accepted, $Drift, $Denied = $Entry.Counts
        $Applicable = $Total - $LicenseMissing - $NoData
        @{
            PartitionKey   = "$($Entry.Key)"
            RowKey         = $Day
            Aligned        = [int]$(if ($Applicable) { [math]::Round((($Compliant + $Accepted) / $Applicable) * 100) } else { 0 })
            Verified       = [int]$(if ($Applicable) { [math]::Round(($Compliant / $Applicable) * 100) } else { 0 })
            Compliant      = [int]$Compliant
            Accepted       = [int]$Accepted
            Drift          = [int]$Drift
            Denied         = [int]$Denied
            LicenseMissing = [int]$LicenseMissing
            Total          = [int]$Total
            Applicable     = [int]$Applicable
            CapturedAt     = $CapturedAt
        }
    })
    Add-CIPPAzDataTableEntity @TrendTable -Entity $Points
}
