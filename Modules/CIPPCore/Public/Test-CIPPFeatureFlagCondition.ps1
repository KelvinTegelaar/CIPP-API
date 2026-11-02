function Test-CIPPFeatureFlagCondition {
    <#
    .SYNOPSIS
        Evaluate the EnabledWhen condition of a feature flag
    .DESCRIPTION
        A flag in FeatureFlags.json may carry an EnabledWhen condition. Get-CIPPFeatureFlag evaluates
        it once, when the flag is seeded into the FeatureFlags table, and starts the flag enabled when
        the condition holds. A user toggle afterwards always wins, so this is a default, not a rule
        that keeps re-applying.

        Known conditions:
          NoClassicStandards - the instance has no classic Standards templates. Baselines replaces
                               classic Standards and Drift and hides their pages, so an install that
                               never created a classic standard can start on the new engine straight
                               away, while an install with standards keeps them until it opts in.
    .PARAMETER Condition
        The condition name as written in FeatureFlags.json.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Condition
    )

    try {
        switch ($Condition) {
            'NoClassicStandards' {
                $Table = Get-CippTable -tablename 'templates'
                $Templates = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2'" -Property RowKey)
                return ($Templates.Count -eq 0)
            }
            default {
                Write-Warning "Unknown feature flag condition '$Condition' - treated as not met"
                return $false
            }
        }
    } catch {
        # Fail closed: an unreadable condition keeps the flag on its static default.
        Write-Warning "Feature flag condition '$Condition' could not be evaluated: $($_.Exception.Message)"
        return $false
    }
}
