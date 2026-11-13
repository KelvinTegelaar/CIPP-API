function Get-CippTestSecureScoreControl {
    <#
    .SYNOPSIS
    Internal helper that grades pinned Defender for Endpoint (MDATP) Secure Score controls against the latest cached snapshot.
    .DESCRIPTION
    Returns one row per control ID, or nothing when the tenant has no cached Secure Score snapshot or control profiles.
    Row Status: 'Pass' (score >= max score), 'Fail', 'Skipped' (control ignored), 'Investigate' (score not numeric),
    or 'N/A' (no MDATP profile, or no score in the latest snapshot because no device is applicable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Tenant,
        [Parameter(Mandatory)] [string[]] $ControlIds
    )

    $Scores = Get-CIPPTestData -TenantFilter $Tenant -Type 'SecureScore'
    $Profiles = Get-CIPPTestData -TenantFilter $Tenant -Type 'SecureScoreControlProfiles'
    if (-not $Scores -or -not $Profiles) { return }

    $Latest = $null
    foreach ($Score in $Scores) {
        if ($Score.createdDateTime -and ($null -eq $Latest -or [datetime]$Score.createdDateTime -gt [datetime]$Latest.createdDateTime)) { $Latest = $Score }
    }
    if ($null -eq $Latest) { return }

    $ScoreByName = @{}
    foreach ($ControlScore in @($Latest.controlScores)) {
        if ($ControlScore.controlName -and -not $ScoreByName.ContainsKey($ControlScore.controlName)) { $ScoreByName[$ControlScore.controlName] = $ControlScore }
    }
    $ProfileById = @{}
    foreach ($ControlProfile in $Profiles) {
        if ($ControlProfile.service -eq 'MDATP' -and $ControlProfile.id -and -not $ProfileById.ContainsKey($ControlProfile.id)) { $ProfileById[$ControlProfile.id] = $ControlProfile }
    }

    foreach ($ControlId in $ControlIds) {
        $ControlProfile = $ProfileById[$ControlId]
        $ControlScore = if ($ControlProfile) { $ScoreByName[$ControlId] }

        $LatestUpdate = $null
        foreach ($Update in @($ControlProfile.controlStateUpdates)) {
            if ($null -eq $Update) { continue }
            $Updated = if ($Update.updatedDateTime) { [datetime]$Update.updatedDateTime } else { [datetime]::MinValue }
            if ($null -eq $LatestUpdate -or $Updated -gt $LatestUpdate.Date) { $LatestUpdate = @{ Date = $Updated; State = $Update.state } }
        }
        $State = if ($LatestUpdate -and -not [string]::IsNullOrWhiteSpace($LatestUpdate.State)) { $LatestUpdate.State } else { 'N/A' }
        $IsIgnored = $State -eq 'ignored'

        $ScoreValue = if ($null -ne $ControlScore.score) { $ControlScore.score -as [double] }
        $MaxScoreValue = if ($null -ne $ControlProfile.maxScore) { $ControlProfile.maxScore -as [double] }

        $StatusReason = $null
        $Status = if (-not $ControlProfile) {
            $StatusReason = 'profile not found'
            'N/A'
        } elseif (-not $ControlScore) {
            $StatusReason = 'no applicable devices'
            'N/A'
        } elseif ($IsIgnored) {
            'Skipped'
        } elseif ($null -eq $ScoreValue -or $null -eq $MaxScoreValue) {
            'Investigate'
        } elseif ($ScoreValue -ge $MaxScoreValue) {
            'Pass'
        } else {
            'Fail'
        }

        $Title = if ($ControlProfile.title) { ($ControlProfile.title -replace '\|', '\|') } else { $ControlId }
        $ControlDisplay = if ($ControlProfile.actionUrl) { "[$Title]($($ControlProfile.actionUrl)) ($ControlId)" } elseif ($Title -ne $ControlId) { "$Title ($ControlId)" } else { $ControlId }
        $StatusDisplay = switch ($Status) {
            'Pass' { '✅ Pass' }
            'Fail' { '❌ Fail' }
            'Investigate' { '⚠️ Investigate' }
            'N/A' { "N/A ($StatusReason)" }
            default { 'Skipped (ignored)' }
        }
        $DisplayScore = if ($null -ne $ControlScore.score) { $ControlScore.score } else { 'N/A' }
        $DisplayMax = if ($null -ne $ControlProfile.maxScore) { $ControlProfile.maxScore } else { 'N/A' }
        $Implementation = if ($ControlScore.implementationStatus) { $ControlScore.implementationStatus -replace '\|', '\|' } else { 'N/A' }

        [PSCustomObject]@{
            ControlId     = $ControlId
            HasProfile    = [bool]$ControlProfile
            Status        = $Status
            IsIgnored     = $IsIgnored
            MarkdownRow   = "| $ControlDisplay | $DisplayScore | $DisplayMax | $Implementation | $State | $StatusDisplay |"
        }
    }
}
