function Get-CIPPScheduledTaskNextRun {
    <#
    .SYNOPSIS
        Next run time for a scheduled task, in unix seconds, or 0 when it does not repeat.
    .DESCRIPTION
        Recurrence is stored as 30m, 1h, 1d and so on; a bare number is a day count, the shape older
        tasks carry. A run further back than one interval is treated as starting now, so a task that
        was disabled or stuck does not replay a backlog of missed runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Recurrence,
        [Parameter(Mandatory = $true)][AllowNull()]$ScheduledTime
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
    if ($Last -lt ($Now - $SecondsToAdd)) { $Last = $Now }

    return $Last + $SecondsToAdd
}
