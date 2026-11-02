function Update-CIPPVersionHistory {
    <#
    .SYNOPSIS
        Records a version-transition event when the instance starts on a different build.
    .DESCRIPTION
        Sync-CippContainerUpdateState notices a restart onto a different build, but only uses
        that to reconcile the update-available flag - the old version and the moment of the
        change are discarded. This warmup step persists them: the last-known version lives in
        a pointer row, and on mismatch with the running APP_VERSION a transition event
        (previous version, new version, image tags, UTC timestamp) is appended to the
        VersionHistory table as durable, queryable history.

        Warmup runs on every node, so concurrent runs must collapse to one event: the event
        RowKey is derived from the previous and new version, making the append idempotent per
        transition - nodes racing through warmup upsert the same row rather than each adding
        a duplicate. A repeat of the same transition (downgrade and back) updates the existing
        event instead of duplicating it.

        The first run on a fresh instance records the pointer only; with no known previous
        version an event would be a guess.

        Never throws; warmup steps are soft-fail by design.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Update-CIPPVersionHistory
    #>
    [CmdletBinding()]
    param()

    $State = [PSCustomObject]@{
        RunningVersion  = $env:APP_VERSION
        PreviousVersion = $null
        Recorded        = $false
        Reason          = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($env:APP_VERSION)) {
            $State.Reason = 'APP_VERSION is not set - nothing to record'
            Write-Information "[Version-History] $($State.Reason)"
            return $State
        }

        $RunningVersion = [string]$env:APP_VERSION
        $ImageTag = [string]($env:IMAGE_TAG ?? '')

        $Table = Get-CIPPTable -TableName 'VersionHistory'
        $Pointer = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Version' and RowKey eq 'Current'" | Select-Object -First 1
        $State.PreviousVersion = $Pointer.Version

        if ($Pointer -and $Pointer.Version -eq $RunningVersion) {
            $State.Reason = "Still on $RunningVersion - no transition to record"
            Write-Information "[Version-History] $($State.Reason)"
            return $State
        }

        $Now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not [string]::IsNullOrWhiteSpace($Pointer.Version)) {
            # Table keys cannot contain / \ # ? or control characters; versions are semver so
            # this is belt-and-braces against a malformed APP_VERSION.
            $RowKey = ('{0}_to_{1}' -f $Pointer.Version, $RunningVersion) -replace '[/\\#?\u0000-\u001f\u007f-\u009f]', '-'
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey     = 'History'
                RowKey           = $RowKey
                PreviousVersion  = [string]$Pointer.Version
                NewVersion       = $RunningVersion
                PreviousImageTag = [string]($Pointer.ImageTag ?? '')
                ImageTag         = $ImageTag
                RecordedAt       = $Now
            } -Force | Out-Null
            $State.Recorded = $true
            $State.Reason = "Recorded version transition '$($Pointer.Version)' -> '$RunningVersion' (tag: $ImageTag)"
        } else {
            $State.Reason = "No previous version on record - storing '$RunningVersion' as the baseline"
        }

        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'Version'
            RowKey       = 'Current'
            Version      = $RunningVersion
            ImageTag     = $ImageTag
            RecordedAt   = $Now
        } -Force | Out-Null

        Write-Information "[Version-History] $($State.Reason)"
    } catch {
        $State.Reason = "Version history recording failed (non-fatal): $($_.Exception.Message)"
        Write-Information "[Version-History] $($State.Reason)"
    }

    return $State
}
