function Sync-CippContainerUpdateState {
    <#
    .SYNOPSIS
    Resolve container update settings and reconcile the stored check result with the running build.

    .DESCRIPTION
    Returns the effective container update settings. Fields that have never been saved resolve
    to the defaults: auto-restart enabled, check every hour, preferred time 23:00. Explicitly
    saved values are respected — including CheckInterval '0' (disabled) and a CheckTime saved
    as an empty string, which means "no preferred time"; only a missing field falls back to
    the default. Both the Status endpoint and the update-check timer consume this, so the
    defaults apply identically to both.

    The ContainerUpdateSettings table is only written when an update check runs, so after a
    restart that applied an update the table keeps reporting the previous build's state —
    "update available" with the old running version — until the next check. This compares the
    stored result against the running APP_VERSION/IMAGE_TAG and clears or recomputes the flag
    locally, without a registry call.
    #>
    [CmdletBinding()]
    param()

    $SettingsTable = Get-CippTable -tablename 'ContainerUpdateSettings'
    $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1

    # Effective schedule settings — defaults apply only to never-saved fields
    $AutoUpdate = if ([string]::IsNullOrWhiteSpace([string]$Settings.AutoUpdate)) { 'true' } else { [string]$Settings.AutoUpdate }
    $CheckInterval = if ([string]::IsNullOrWhiteSpace([string]$Settings.CheckInterval)) { '1h' } else { [string]$Settings.CheckInterval }
    $CheckTime = if ($null -eq $Settings.CheckTime) { '23' } else { [string]$Settings.CheckTime }

    $RunningVersion = $env:APP_VERSION
    $StoredRunning = [string]($Settings.RunningVersion ?? '')
    $StoredRemote = [string]($Settings.RemoteVersion ?? '')
    $CheckedTag = [string]($Settings.CheckedTag ?? '')
    $UpdateAvailable = [string]($Settings.UpdateAvailable ?? 'false')

    $NeedsWrite = $false
    if ($Settings -and $RunningVersion -and $StoredRunning -and $StoredRunning -ne $RunningVersion) {
        # The container restarted onto a different build since the last check.
        $RunningTag = $env:IMAGE_TAG
        if ($CheckedTag -and $RunningTag -and $CheckedTag -ne $RunningTag) {
            # The last check ran against a different channel tag — its result no longer applies.
            $UpdateAvailable = 'False'
        } else {
            $UpdateAvailable = [string][bool]($StoredRemote -and $StoredRemote -ne $RunningVersion)
        }
        Write-Information "Container update state reconciled: running build changed '$StoredRunning' -> '$RunningVersion', UpdateAvailable=$UpdateAvailable"
        $StoredRunning = $RunningVersion
        $NeedsWrite = $true
    }

    $Entity = @{
        PartitionKey    = 'Settings'
        RowKey          = 'UpdateConfig'
        AutoUpdate      = $AutoUpdate
        CheckInterval   = $CheckInterval
        CheckTime       = $CheckTime
        LastCheck       = [string]($Settings.LastCheck ?? '')
        UpdateAvailable = $UpdateAvailable
        RunningVersion  = $StoredRunning
        RemoteVersion   = $StoredRemote
        RemoteDigest    = [string]($Settings.RemoteDigest ?? '')
        RemoteBuildDate = [string]($Settings.RemoteBuildDate ?? '')
        CheckedTag      = $CheckedTag
    }
    if ($NeedsWrite) {
        Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null
    }
    return [pscustomobject]$Entity
}
