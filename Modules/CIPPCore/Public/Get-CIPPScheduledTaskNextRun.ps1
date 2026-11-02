function Get-CIPPScheduledTaskNextRun {
    <#
    .SYNOPSIS
        Next run time for a scheduled task, in unix seconds, or 0 when it does not repeat.
    .DESCRIPTION
        Recurrence is stored as 30m, 1h, 1d and so on; a bare number is a day count, the shape older
        tasks carry. The next run is the first ScheduledTime + n * interval after now, so a late run keeps
        its original slot and a task that was disabled or stuck does not replay missed runs.
        -Due returns the latest slot at or before now instead, for running a task early without moving its slots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Recurrence,
        [Parameter(Mandatory = $true)][AllowNull()]$ScheduledTime,
        [switch]$Due
    )

    $Value = [string]$Recurrence
    if ($Value -match '^\d+$') { $Value = '{0}d' -f $Value }

    $SecondsToAdd = switch -Regex ($Value) {
        '(\d+)m$' { [int64]$Matches[1] * 60 }
        '(\d+)h$' { [int64]$Matches[1] * 3600 }
        '(\d+)d$' { [int64]$Matches[1] * 86400 }
        default { 0 }
    }
    if ($SecondsToAdd -le 0) { return 0 }

    $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    $Last = [int64]($ScheduledTime ?? 0)
    if ($Due) {
        if ($Last -le $Now) { return $Last }
        return $Last - [int64][Math]::Ceiling(($Last - $Now) / $SecondsToAdd) * $SecondsToAdd
    }
    if ($Last -ge $Now) { return $Last + $SecondsToAdd }

    return $Last + ([int64][Math]::Floor(($Now - $Last) / $SecondsToAdd) + 1) * $SecondsToAdd
}
