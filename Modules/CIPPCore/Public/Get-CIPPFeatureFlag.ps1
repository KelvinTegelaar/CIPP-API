function Get-CIPPFeatureFlag {
    <#
    .SYNOPSIS
        Get the state of a feature flag or all feature flags
    .DESCRIPTION
        Retrieves the current state of a feature flag from the FeatureFlags table, falling back to the default state from JSON if not found.
        If Id is not specified, returns all feature flags.

        Defaults are seeded into the table the first time a flag is read. A flag may carry an
        EnabledWhen condition in FeatureFlags.json (see Test-CIPPFeatureFlagCondition): when the
        condition holds at seed time the flag starts enabled instead of using its static Enabled
        default. A row that was auto-seeded by an older release (no LastModified, so never toggled
        by a user) is re-seeded once when a condition is introduced, so a new release can change
        the default for installs that never chose. A user toggle (LastModified set) always wins.
    .PARAMETER Id
        The ID of the feature flag to retrieve. If not specified, returns all feature flags.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id
    )

    try {
        # Get feature flags from JSON
        $FeatureFlags = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\FeatureFlags.json')) | ConvertFrom-Json

        if ($Id) {
            $FeatureFlags = @($FeatureFlags | Where-Object { $_.Id -eq $Id })
            if ($FeatureFlags.Count -eq 0) {
                Write-Warning "Feature flag '$Id' not found in FeatureFlags.json"
                return $null
            }
        }

        # Get all table flags once
        $Table = Get-CIPPTable -TableName 'FeatureFlags'
        $TableFlags = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'FeatureFlag'"

        # Several flags can share one condition; evaluate each condition at most once per call.
        $ConditionResults = @{}

        $Results = foreach ($FeatureFlag in $FeatureFlags) {
            $TableFlag = $TableFlags | Where-Object { $_.RowKey -eq $FeatureFlag.Id }
            $Condition = [string]$FeatureFlag.EnabledWhen

            # Seed when the row is missing, or re-seed an auto-seeded row (never toggled by a user)
            # that has not had this release's condition applied yet.
            $NeedsSeed = (-not $TableFlag) -or (
                $Condition -and -not $TableFlag.LastModified -and [string]$TableFlag.DefaultRule -ne $Condition
            )

            if ($NeedsSeed) {
                $Enabled = [bool]$FeatureFlag.Enabled
                if ($Condition) {
                    if (-not $ConditionResults.ContainsKey($Condition)) {
                        $ConditionResults[$Condition] = Test-CIPPFeatureFlagCondition -Condition $Condition
                    }
                    if ($ConditionResults[$Condition]) { $Enabled = $true }
                }

                # Only RowKey, Enabled and the applied default rule are stored; everything else comes from JSON.
                $Entity = @{
                    PartitionKey = 'FeatureFlag'
                    RowKey       = $FeatureFlag.Id
                    Enabled      = $Enabled
                }
                if ($Condition) { $Entity.DefaultRule = $Condition }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
            } else {
                $Enabled = $TableFlag.Enabled
            }

            [PSCustomObject]@{
                Id              = $FeatureFlag.Id
                Name            = $FeatureFlag.Name
                Description     = $FeatureFlag.Description
                AllowUserToggle = $FeatureFlag.AllowUserToggle
                Timers          = $FeatureFlag.Timers
                Endpoints       = $FeatureFlag.Endpoints
                Pages           = $FeatureFlag.Pages
                HidesPages      = $FeatureFlag.HidesPages
                Hidden          = [bool]$FeatureFlag.Hidden
                Enabled         = $Enabled
            }
        }

        if ($Id) {
            return ($Results | Select-Object -First 1)
        }
        return $Results
    } catch {
        $ErrorMsg = if ($Id) { "'$Id'" } else { 'flags' }
        Write-Error "Error retrieving feature $($ErrorMsg): $($_.Exception.Message)"
        return $null
    }
}
