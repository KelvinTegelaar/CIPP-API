function Initialize-CIPPTimezone {
    <#
    .SYNOPSIS
    Resolves the instance timezone at warmup and applies it to the PowerShell environment
    and the Craft scheduler.

    .DESCRIPTION
    Reads the TimeSettings row from the Config table. When no timezone has been configured,
    derives one from the Azure region the instance runs in ($env:REGION_NAME via
    Get-CIPPRegionTimezone) and persists it, instead of silently leaving everything on UTC.

    Persisting matters because the consumers are split: Write-LogMessage and Invoke-ListLogs
    read $env:CIPP_TIMEZONE, while Get-CIPPTimerFunctions and Start-ContainerUpdateCheck read
    the Config table directly. Setting only the environment variable would put log
    partitioning on local time while every cron kept firing on UTC.

    The timezone is computed first and applied once at the end, so CIPP_TIMEZONE, CraftTZ and
    the scheduler always agree no matter which branch was taken.
    #>
    [CmdletBinding()]
    param()

    $Timezone = 'UTC'

    try {
        $ConfigTable = Get-CIPPTable -tablename Config
        $Filter = "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'"

        # Warmup can run before the storage layer is fully up, and in that window the query
        # returns EMPTY rather than throwing - indistinguishable from "no timezone configured".
        # Acting on that would derive a timezone and overwrite whatever the operator had
        # explicitly chosen, so an empty result has to be corroborated before it is trusted.
        #
        # The corroboration: if ANY row in the Config table is readable then storage is up and
        # the TimeSettings row is genuinely absent. A completely empty Config table means either
        # a brand-new instance (safe - there is no choice to overwrite) or storage that is not
        # ready yet, so retry briefly before concluding. Observed live: this read came back empty
        # on one restart while the row existed, and a retry moments later returned it.
        #
        # No -Property projection: it is a server-side $select, and TimezoneSource /
        # DetectedRegion are read below.
        $TimeSettings = $null
        for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
            $TimeSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter -First 1
            if ($TimeSettings.Timezone) { break }
            if (Get-CIPPAzDataTableEntity @ConfigTable -First 1) { break }
            if ($Attempt -lt 4) {
                Write-Information "[Timezone-Init] Config table returned no rows (attempt $Attempt/4) - storage may still be starting, retrying before assuming no timezone is set"
                Start-Sleep -Milliseconds 750
            }
        }

        if ($TimeSettings.Timezone) {
            $null = [TimeZoneInfo]::FindSystemTimeZoneById($TimeSettings.Timezone)
            $Timezone = [string]$TimeSettings.Timezone
            $Source = $TimeSettings.TimezoneSource ?? 'User'
            Write-Information "[Timezone-Init] Timezone set to $Timezone (source: $Source)"
        } else {
            # Nothing configured - fall back to the region we are deployed in rather than UTC.
            $Region = $env:REGION_NAME
            $Derived = Get-CIPPRegionTimezone -Region $Region
            try {
                $null = [TimeZoneInfo]::FindSystemTimeZoneById($Derived)
            } catch {
                Write-Warning "[Timezone-Init] Derived timezone '$Derived' for region '$Region' is not a valid system timezone, using UTC"
                $Derived = 'UTC'
            }

            if ($Derived -eq 'UTC') {
                Write-Information "[Timezone-Init] No timezone configured and no region match (region: '$Region'), using UTC"
            } else {
                $Timezone = $Derived
                # Warmup runs on every node. All nodes read the same REGION_NAME and the same
                # map, so they derive an identical value and a race would be a no-op - but only
                # the main node writes, and it re-reads first to collapse the window. Offload
                # nodes still apply the derived value to their own environment below, so no node
                # is left on UTC while another is on local time.
                #
                # (Offload apps are assumed to sit in the same region as the main app. If that
                # ever changes, timers still follow the table and stay correct; only that node's
                # log date partitioning would drift.)
                if (-not (Test-CippOffloadFunctionApp)) {
                    try {
                        $Recheck = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'" -First 1
                        if (-not $Recheck.Timezone) {
                            # UpsertMerge, not -Force: -Force is a replace and would wipe any
                            # sibling properties on the row.
                            Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
                                PartitionKey   = 'TimeSettings'
                                RowKey         = 'TimeSettings'
                                Timezone       = $Timezone
                                TimezoneSource = 'AutoRegion'
                                DetectedRegion = [string]$Region
                            } -OperationType UpsertMerge | Out-Null
                            Write-Information "[Timezone-Init] No timezone configured - derived '$Timezone' from region '$Region' and saved it"
                        } else {
                            Write-Information "[Timezone-Init] Another node set the timezone to $($Recheck.Timezone) first, using that"
                            $Timezone = [string]$Recheck.Timezone
                        }
                    } catch {
                        # Never let a write failure break node startup - the environment is still
                        # set from the derived value below and the next warmup retries.
                        Write-Warning "[Timezone-Init] Could not save derived timezone: $($_.Exception.Message)"
                    }
                } else {
                    Write-Information "[Timezone-Init] Derived '$Timezone' from region '$Region' (offload node - main node persists it)"
                }
            }
        }
    } catch {
        $Timezone = 'UTC'
        Write-Warning "[Timezone-Init] Failed to load timezone, defaulting to UTC: $_"
    }

    # Single exit point so every path agrees. CraftTZ was previously set only when a timezone
    # was already configured, leaving the scheduler on a stale value everywhere else.
    try { [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CIPP_TIMEZONE', $Timezone) } catch { Write-Warning "[Timezone-Init] Could not set CIPP_TIMEZONE: $($_.Exception.Message)" }
    try { [Craft.Services.PowerShellRunnerService]::SetProcessEnvVar('CraftTZ', $Timezone) } catch { Write-Warning "[Timezone-Init] Could not set CraftTZ: $($_.Exception.Message)" }

    # The scheduler reads CraftTZ once, when it starts. If it already did, the assignment above
    # is too late and cron would stay on UTC until the next restart - so apply it directly too.
    # SetTimezone reseeds the affected tasks, so this cannot double-fire or skip one. It throws
    # if the scheduler is not constructed yet, in which case CraftTZ covers us.
    try { [Craft.Services.SchedulerBridge]::SetTimezone($Timezone) } catch { Write-Information "[Timezone-Init] Scheduler not ready for a timezone update (it will read CraftTZ): $($_.Exception.Message)" }
}
