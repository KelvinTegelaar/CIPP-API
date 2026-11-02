function Get-CippAuditLogReconciliationWindows {
    <#
    .SYNOPSIS
        Compute the 12-hour reconciliation audit-log windows a tenant is missing.
    .DESCRIPTION
        The fast 35-minute path searches each period soon after it closes, so late-landing / backfilled
        audit events (Microsoft can publish them hours later) can be missed. This helper produces wide
        catch-all windows aligned to 00:00-12:00 and 12:00-00:00 UTC, each created 3 hours after the
        block closes (a generous settle so backfilled data has landed). They flow through the normal
        download/process path; alerting dedups by record id, so overlap with the fast path is harmless.
    .PARAMETER ExistingRows
        The tenant's current AuditLogCoverage rows. Only reconciliation rows (RowKey 'RECON-*') are
        considered when finding gaps.
    .PARAMETER Now
        Reference time (UTC). Defaults to now.
    .OUTPUTS
        Array of [pscustomobject]@{ RowKey; WindowStart; WindowEnd } sorted oldest-first. RowKey is
        'RECON-<windowStart yyyyMMddHHmmss>'.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$ExistingRows,
        [datetime]$Now = (Get-Date).ToUniversalTime(),
        [int]$SettleHours = 3,
        [int]$HorizonHours = 24,
        [int]$MaxPerRun = 6
    )

    $Now = $Now.ToUniversalTime()

    # Newest 12h block end (00:00 / 12:00 UTC) whose close is at least SettleHours in the past.
    $T = $Now.AddHours(-$SettleHours)
    $BoundaryHour = if ($T.Hour -lt 12) { 0 } else { 12 }
    $NewestEnd = [datetime]::new($T.Year, $T.Month, $T.Day, $BoundaryHour, 0, 0, [System.DateTimeKind]::Utc)
    $HorizonStart = $Now.AddHours(-$HorizonHours)

    $ExistingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Row in $ExistingRows) {
        if ($Row.RowKey -like 'RECON-*') { [void]$ExistingKeys.Add([string]$Row.RowKey) }
    }

    # No reconciliation history: seed only the newest settled block (avoid a first-run backfill spike;
    # the fast 35-min path already covers recent history). Established tenants backfill gaps below.
    if ($ExistingKeys.Count -eq 0) {
        $Start = $NewestEnd.AddHours(-12)
        if ($Start -lt $HorizonStart) { return @() }
        return , ([pscustomobject]@{ RowKey = 'RECON-' + $Start.ToString('yyyyMMddHHmmss'); WindowStart = $Start; WindowEnd = $NewestEnd })
    }

    $Owed = [System.Collections.Generic.List[object]]::new()
    $End = $NewestEnd
    while ($End -ge $HorizonStart) {
        $Start = $End.AddHours(-12)
        $Key = 'RECON-' + $Start.ToString('yyyyMMddHHmmss')
        if (-not $ExistingKeys.Contains($Key)) {
            $Owed.Add([pscustomobject]@{ RowKey = $Key; WindowStart = $Start; WindowEnd = $End })
        }
        $End = $End.AddHours(-12)
    }

    $Owed.Reverse()
    if ($Owed.Count -gt $MaxPerRun) {
        return @($Owed[0..($MaxPerRun - 1)])
    }
    return @($Owed)
}
