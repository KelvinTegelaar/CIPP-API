function Get-CIPPBaselineSecureScoreRemediationState {
    <#
    .SYNOPSIS
        Prepare hook for SecureScoreRemediation: secure score control states.
    .DESCRIPTION
        A secure score control profile has no top-level state - the effective state is the
        NEWEST controlStateUpdates entry, and no entries at all means the control sits at
        default. That derivation is the classic's and it is the whole reason this is a
        hook.

        Grades each configured control (three lists: back to default, ignored, marked
        third-party) against its effective state. Controls outside the configured lists are
        never graded - operators mark controls for their own reasons.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Profiles = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles')
    if ($Profiles.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles')) {
        return @{ Current = $null }
    }

    $States = @{}
    foreach ($ControlProfile in $Profiles) {
        $Latest = @($ControlProfile.controlStateUpdates) | Sort-Object updatedDateTime | Select-Object -Last 1
        $States["$($ControlProfile.id)"] = $(if ([string]::IsNullOrEmpty("$($Latest.state)")) { 'default' } else { "$($Latest.state)" })
    }

    $Unwrap = { param($Value) @(@($Value) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    $Wanted = [System.Collections.Generic.List[object]]::new()
    foreach ($Control in (& $Unwrap $Item.Variables.Default)) { $Wanted.Add(@{ Control = $Control; State = 'default'; Reason = 'Default' }) }
    foreach ($Control in (& $Unwrap $Item.Variables.Ignored)) { $Wanted.Add(@{ Control = $Control; State = 'ignored'; Reason = 'Ignored' }) }
    foreach ($Control in (& $Unwrap $Item.Variables.ThirdParty)) { $Wanted.Add(@{ Control = $Control; State = 'thirdParty'; Reason = 'ThirdParty' }) }
    foreach ($Control in (& $Unwrap $Item.Variables.Reviewed)) { $Wanted.Add(@{ Control = $Control; State = 'reviewed'; Reason = 'Reviewed' }) }
    if ($Wanted.Count -eq 0) { return @{ Current = $null } }

    $Drifted = [System.Collections.Generic.List[object]]::new()
    foreach ($Want in $Wanted) {
        $Effective = "$($States["$($Want.Control)"])"
        if ($Effective -ne $Want.State) {
            $Drifted.Add([PSCustomObject]@{ Control = "$($Want.Control)"; State = "$($Want.State)"; Reason = "$($Want.Reason)"; CurrentState = $Effective })
        }
    }

    $Current = [PSCustomObject]@{
        controlsOutOfState = @($Drifted | ForEach-Object { "$($_.Control): '$($_.CurrentState)' should be '$($_.State)'" } | Sort-Object)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'driftedControls' -NotePropertyValue @($Drifted)

    @{
        Expected = [PSCustomObject]@{ controlsOutOfState = @() }
        Current  = $Current
    }
}
