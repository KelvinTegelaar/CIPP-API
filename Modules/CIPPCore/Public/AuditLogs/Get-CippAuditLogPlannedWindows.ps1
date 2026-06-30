function Get-CippAuditLogPlannedWindows {
    <#
    .SYNOPSIS
        Compute the 35-minute audit-log search windows a tenant is missing (gaps + the newest settled).
    .DESCRIPTION
        Pure helper for the V2 audit-log pipeline. Windows are 35 minutes long on a 30-minute stride,
        so consecutive windows overlap by 5 minutes (covers boundary stragglers; alerting dedups by
        record id). Window ENDS sit on the 30-minute grid minus the settle (i.e. :25 / :55), which is
        exactly `floor_to_30min(now) - settle`. With the planner timer firing at :00/:15/:30/:45 and a
        5-minute settle, a fresh window becomes creatable exactly at a :00/:30 tick - no tick delay -
        and the :15/:45 ticks naturally have no new window (they do retries + download/process).

        Backfill of older gaps is bounded by -HorizonHours and capped at -MaxPerRun per call (oldest
        first). A brand-new tenant is seeded with only the newest settled window.
    .PARAMETER ExistingRows
        The tenant's current AuditLogCoverage rows. Reconciliation rows (RowKey 'RECON-*') are ignored
        here; only regular 14-digit window keys are considered.
    .PARAMETER Now
        Reference time (UTC). Defaults to now.
    .OUTPUTS
        Array of [pscustomobject]@{ RowKey; WindowStart; WindowEnd } sorted oldest-first.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$ExistingRows,
        [datetime]$Now = (Get-Date).ToUniversalTime(),
        [int]$SettleMinutes = 5,
        [int]$WindowMinutes = 35,
        [int]$StrideMinutes = 30,
        [int]$HorizonHours = 24,
        [int]$MaxPerRun = 6
    )

    $Now = $Now.ToUniversalTime()

    # Newest window end: floor to the 30-min grid, minus the settle (lands on :25 / :55).
    $FloorMinute = $Now.Minute - ($Now.Minute % $StrideMinutes)
    $Floor = [datetime]::new($Now.Year, $Now.Month, $Now.Day, $Now.Hour, $FloorMinute, 0, [System.DateTimeKind]::Utc)
    $NewestEnd = $Floor.AddMinutes(-$SettleMinutes)

    $HorizonStart = $Now.AddHours(-$HorizonHours)

    # Existing regular window keys (ignore reconciliation rows).
    $ExistingKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ExistingStarts = [System.Collections.Generic.List[datetime]]::new()
    foreach ($Row in $ExistingRows) {
        if ($Row.RowKey -notmatch '^\d{14}$') { continue }
        [void]$ExistingKeys.Add([string]$Row.RowKey)
        if ($null -ne $Row.WindowStart) {
            try { $ExistingStarts.Add(([datetimeoffset]$Row.WindowStart).UtcDateTime) } catch {}
        }
    }

    # Brand-new tenant: seed only the newest settled window.
    if ($ExistingStarts.Count -eq 0) {
        $Start = $NewestEnd.AddMinutes(-$WindowMinutes)
        if ($Start -lt $HorizonStart) { return @() }
        return , ([pscustomobject]@{
                RowKey      = $Start.ToString('yyyyMMddHHmmss')
                WindowStart = $Start
                WindowEnd   = $NewestEnd
            })
    }

    # Established tenant: backfill missing windows from the lower bound up to NewestEnd (oldest first).
    $EarliestExisting = ($ExistingStarts | Measure-Object -Minimum).Minimum
    $LowerEnd = if ($EarliestExisting -gt $HorizonStart) { $EarliestExisting.AddMinutes($WindowMinutes) } else { $HorizonStart.AddMinutes($WindowMinutes) }

    $Owed = [System.Collections.Generic.List[object]]::new()
    $End = $NewestEnd
    while ($End -ge $LowerEnd) {
        $Start = $End.AddMinutes(-$WindowMinutes)
        $Key = $Start.ToString('yyyyMMddHHmmss')
        if (-not $ExistingKeys.Contains($Key)) {
            $Owed.Add([pscustomobject]@{ RowKey = $Key; WindowStart = $Start; WindowEnd = $End })
        }
        $End = $End.AddMinutes(-$StrideMinutes)
    }

    # $Owed is newest-first from the loop; reorder to oldest-first ([0]=oldest, [-1]=newest).
    $Owed.Reverse()
    if ($Owed.Count -le $MaxPerRun) {
        return @($Owed)
    }

    # Backlog exceeds the per-run cap: always include the NEWEST window so the live period can
    # be created promptly (current-first, see Push-AuditLogSearchCreationV2), plus the oldest
    # (MaxPerRun-1) so historical gaps still drain - oldest first - before they age out of the
    # horizon. Without seeding the newest here it would never be Planned during a backlog.
    $Newest = $Owed[$Owed.Count - 1]
    $Backfill = @($Owed[0..($MaxPerRun - 2)])
    return @($Backfill + $Newest)
}
