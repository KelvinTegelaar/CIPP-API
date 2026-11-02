# Pester tests for Get-CippAuditLogPlannedWindows - the V2 audit-log window planner.
#
# The geometry here is load-bearing and was previously untested. Three properties matter:
#
#   * 35-minute windows on a 30-minute stride, so consecutive windows OVERLAP by 5 minutes and
#     coverage is continuous. The overlap is deliberate and is only safe because alerting
#     de-duplicates by record id in Invoke-CippWebhookProcessing's claim-insert.
#   * Window ends sit on `floor_to_30min(now) - settle`. With a 20-minute settle that is the
#     :10/:40 grid, and with the planner firing at :00/:15/:30/:45 a fresh window becomes
#     creatable exactly at a :00/:30 tick - no tick delay - while :15/:45 produce nothing new.
#   * The settle is the grace Microsoft gets to publish an event before the window covering it is
#     searched. Changing it moves the grid, which is why the tick behaviour is pinned here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/Get-CippAuditLogPlannedWindows.ps1')

    function New-Row {
        param([datetime]$Start)
        [pscustomobject]@{
            RowKey      = $Start.ToString('yyyyMMddHHmmss')
            WindowStart = $Start
        }
    }
    # [datetimeoffset], not [datetime]::Parse + SpecifyKind: Parse converts a 'Z' literal to LOCAL
    # time and SpecifyKind then merely relabels it UTC without converting, so every assertion below
    # would be off by this machine's UTC offset.
    function Utc { param([string]$Text) ([datetimeoffset]$Text).UtcDateTime }
}

Describe 'Get-CippAuditLogPlannedWindows' {

    Context 'window geometry' {

        It 'produces 35-minute windows' {
            $Owed = @(Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:00:00Z'))
            $Owed.Count | Should -Be 1
            ($Owed[0].WindowEnd - $Owed[0].WindowStart).TotalMinutes | Should -Be 35
        }

        It 'ends on the :10/:40 grid, being floor_to_30min(now) minus the 20-minute settle' {
            (Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:00:00Z')).WindowEnd.ToString('HH:mm') | Should -Be '09:40'
            (Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:29:59Z')).WindowEnd.ToString('HH:mm') | Should -Be '09:40'
            (Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:30:00Z')).WindowEnd.ToString('HH:mm') | Should -Be '10:10'
        }

        It 'advances on a 30-minute stride, so consecutive windows overlap by 5 minutes' {
            # Feed the first window back as history and ask again half an hour later.
            $First = Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:00:00Z')
            $Second = Get-CippAuditLogPlannedWindows -ExistingRows @((New-Row $First.WindowStart)) -Now (Utc '2026-08-14T10:30:00Z')

            ($Second.WindowStart - $First.WindowStart).TotalMinutes | Should -Be 30
            # Overlap, not a gap: the second window starts before the first one ends.
            $Second.WindowStart | Should -BeLessThan $First.WindowEnd
            ($First.WindowEnd - $Second.WindowStart).TotalMinutes | Should -Be 5
        }
    }

    Context 'tick behaviour' {
        # The planner fires at :00/:15/:30/:45. A fresh window must be creatable at :00 and :30
        # with no delay, and the intermediate ticks must produce nothing - they exist to do
        # retries and download/process work.

        BeforeEach {
            # History through the window ending 09:40, i.e. the one the 10:00 tick would create.
            $script:History = @((New-Row (Utc '2026-08-14T09:05:00Z')))
        }

        It 'offers nothing at the :15 tick when the :00 window already exists' {
            @(Get-CippAuditLogPlannedWindows -ExistingRows $script:History -Now (Utc '2026-08-14T10:15:00Z')).Count | Should -Be 0
        }

        It 'offers nothing at the :45 tick either' {
            $Later = $script:History + @((New-Row (Utc '2026-08-14T09:35:00Z')))
            @(Get-CippAuditLogPlannedWindows -ExistingRows $Later -Now (Utc '2026-08-14T10:45:00Z')).Count | Should -Be 0
        }

        It 'offers exactly one fresh window at the :30 tick' {
            $Owed = @(Get-CippAuditLogPlannedWindows -ExistingRows $script:History -Now (Utc '2026-08-14T10:30:00Z'))
            $Owed.Count | Should -Be 1
            $Owed[0].WindowStart.ToString('HH:mm') | Should -Be '09:35'
            $Owed[0].WindowEnd.ToString('HH:mm') | Should -Be '10:10'
        }
    }

    Context 'seeding and backfill' {

        It 'seeds a brand-new tenant with only the newest settled window' {
            # Not a 24-hour backfill on first sight of a tenant.
            @(Get-CippAuditLogPlannedWindows -ExistingRows @() -Now (Utc '2026-08-14T10:00:00Z')).Count | Should -Be 1
        }

        It 'backfills gaps oldest-first and caps the run' {
            # One ancient row, so the planner sees a long gap between it and now.
            $Owed = @(Get-CippAuditLogPlannedWindows -ExistingRows @((New-Row (Utc '2026-08-14T00:05:00Z'))) -Now (Utc '2026-08-14T10:00:00Z'))
            $Owed.Count | Should -Be 6
            # Oldest first, so historical gaps drain before they age out of the horizon.
            $Owed[0].WindowStart | Should -BeLessThan $Owed[1].WindowStart
        }

        It 'always includes the newest window when the backlog exceeds the cap' {
            # Otherwise the live period would never be Planned while a backlog drains, and
            # alerting would stall on current activity until history caught up.
            $Owed = @(Get-CippAuditLogPlannedWindows -ExistingRows @((New-Row (Utc '2026-08-14T00:05:00Z'))) -Now (Utc '2026-08-14T10:00:00Z'))
            $Owed[-1].WindowEnd.ToString('HH:mm') | Should -Be '09:40'
        }

        It 'ignores reconciliation rows when finding gaps' {
            # RECON-* rows are the 12-hour catch-all path and must not suppress a regular window.
            $Recon = @([pscustomobject]@{ RowKey = 'RECON-20260814000000'; WindowStart = (Utc '2026-08-14T00:00:00Z') })
            @(Get-CippAuditLogPlannedWindows -ExistingRows $Recon -Now (Utc '2026-08-14T10:00:00Z')).Count | Should -Be 1
        }
    }
}
