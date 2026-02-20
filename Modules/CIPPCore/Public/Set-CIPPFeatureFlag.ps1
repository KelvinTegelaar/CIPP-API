function Set-CIPPFeatureFlag {
    <#
    .SYNOPSIS
        Set the state of a feature flag
    .DESCRIPTION
        Updates the state of a feature flag in the FeatureFlags table
    .PARAMETER Id
        The ID of the feature flag to update
    .PARAMETER Enabled
        The new enabled state for the feature flag (true/false)
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    try {
        # Get feature flags from JSON to validate
        $FeatureFlagsPath = Join-Path -Path $PSScriptRoot -ChildPath '../lib/data/FeatureFlags.json'
        $FeatureFlags = Get-Content -Path $FeatureFlagsPath -Raw | ConvertFrom-Json

        # Find the requested feature flag in JSON
        $FeatureFlag = $FeatureFlags | Where-Object { $_.Id -eq $Id }

        if (-not $FeatureFlag) {
            Write-Error "Feature flag '$Id' not found in FeatureFlags.json"
            return $false
        }

        # Check if user toggle is allowed
        if (-not $FeatureFlag.AllowUserToggle) {
            Write-Warning "Feature flag '$Id' does not allow user toggling"
            return $false
        }

        if ($PSCmdlet.ShouldProcess($Id, "Set feature flag enabled to $Enabled")) {
            # Update or create the table entry (only store RowKey and Enabled)
            $Table = Get-CIPPTable -TableName 'FeatureFlags'

            $Entity = @{
                PartitionKey = 'FeatureFlag'
                RowKey       = $Id
                Enabled      = $Enabled
                LastModified = (Get-Date).ToUniversalTime().ToString('o')
            }

            $Result = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            Write-Information "Feature flag '$Id' set to $Enabled"
            return $true
        }
    } catch {
        Write-Error "Error setting feature flag '$Id': $($_.Exception.Message)"
        return $false
    }
}
