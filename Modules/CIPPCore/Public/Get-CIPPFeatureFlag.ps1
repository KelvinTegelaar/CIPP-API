function Get-CIPPFeatureFlag {
    <#
    .SYNOPSIS
        Get the state of a feature flag or all feature flags
    .DESCRIPTION
        Retrieves the current state of a feature flag from the FeatureFlags table, falling back to the default state from JSON if not found.
        If Id is not specified, returns all feature flags.
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
        $FeatureFlagsPath = Join-Path -Path $PSScriptRoot -ChildPath '../lib/data/FeatureFlags.json'
        $FeatureFlags = Get-Content -Path $FeatureFlagsPath -Raw | ConvertFrom-Json

        # Get all table flags once
        $Table = Get-CIPPTable -TableName 'FeatureFlags'
        $TableFlags = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'FeatureFlag'"

        # If Id is specified, return single flag
        if ($Id) {
            $FeatureFlag = $FeatureFlags | Where-Object { $_.Id -eq $Id }

            if (-not $FeatureFlag) {
                Write-Warning "Feature flag '$Id' not found in FeatureFlags.json"
                return $null
            }

            $TableFlag = $TableFlags | Where-Object { $_.RowKey -eq $Id }

            if ($TableFlag) {
                # Return the table version with metadata from JSON
                # Parse JSON arrays from table storage
                $Timers = if ($TableFlag.Timers) { $TableFlag.Timers | ConvertFrom-Json } else { $FeatureFlag.Timers }
                $Endpoints = if ($TableFlag.Endpoints) { $TableFlag.Endpoints | ConvertFrom-Json } else { $FeatureFlag.Endpoints }
                $Pages = if ($TableFlag.Pages) { $TableFlag.Pages | ConvertFrom-Json } else { $FeatureFlag.Pages }

                return [PSCustomObject]@{
                    Id              = $TableFlag.RowKey
                    Name            = $TableFlag.Name
                    Description     = $TableFlag.Description
                    AllowUserToggle = $FeatureFlag.AllowUserToggle
                    Timers          = $Timers
                    Endpoints       = $Endpoints
                    Pages           = $Pages
                    Enabled         = $TableFlag.Enabled
                }
            } else {
                # Insert feature flag into table with defaults from JSON
                $Entity = @{
                    PartitionKey = 'FeatureFlag'
                    RowKey       = $FeatureFlag.Id
                    Enabled      = $FeatureFlag.Enabled
                    Timers       = [string]($FeatureFlag.Timers | ConvertTo-Json -Compress)
                    Endpoints    = [string]($FeatureFlag.Endpoints | ConvertTo-Json -Compress)
                    Pages        = [string]($FeatureFlag.Pages | ConvertTo-Json -Compress)
                    Name         = [string]$FeatureFlag.Name
                    Description  = [string]$FeatureFlag.Description
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

                # Return the initialized feature flag
                return [PSCustomObject]@{
                    Id              = $FeatureFlag.Id
                    Name            = $FeatureFlag.Name
                    Description     = $FeatureFlag.Description
                    AllowUserToggle = $FeatureFlag.AllowUserToggle
                    Timers          = $FeatureFlag.Timers
                    Endpoints       = $FeatureFlag.Endpoints
                    Pages           = $FeatureFlag.Pages
                    Enabled         = $FeatureFlag.Enabled
                }
            }
        } else {
            # Return all feature flags
            $Results = foreach ($FeatureFlag in $FeatureFlags) {
                $TableFlag = $TableFlags | Where-Object { $_.RowKey -eq $FeatureFlag.Id }

                if ($TableFlag) {
                    # Parse JSON arrays from table storage
                    $Timers = if ($TableFlag.Timers) { $TableFlag.Timers | ConvertFrom-Json } else { $FeatureFlag.Timers }
                    $Endpoints = if ($TableFlag.Endpoints) { $TableFlag.Endpoints | ConvertFrom-Json } else { $FeatureFlag.Endpoints }
                    $Pages = if ($TableFlag.Pages) { $TableFlag.Pages | ConvertFrom-Json } else { $FeatureFlag.Pages }

                    [PSCustomObject]@{
                        Id              = $TableFlag.RowKey
                        Name            = $TableFlag.Name
                        Description     = $TableFlag.Description
                        AllowUserToggle = $FeatureFlag.AllowUserToggle
                        Timers          = $Timers
                        Endpoints       = $Endpoints
                        Pages           = $Pages
                        Enabled         = $TableFlag.Enabled
                    }
                } else {
                    # Insert feature flag into table with defaults from JSON
                    $Entity = @{
                        PartitionKey = 'FeatureFlag'
                        RowKey       = $FeatureFlag.Id
                        Enabled      = $FeatureFlag.Enabled
                        Timers       = [string]($FeatureFlag.Timers | ConvertTo-Json -Compress)
                        Endpoints    = [string]($FeatureFlag.Endpoints | ConvertTo-Json -Compress)
                        Pages        = [string]($FeatureFlag.Pages | ConvertTo-Json -Compress)
                        Name         = [string]$FeatureFlag.Name
                        Description  = [string]$FeatureFlag.Description
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

                    # Return the initialized feature flag
                    [PSCustomObject]@{
                        Id              = $FeatureFlag.Id
                        Name            = $FeatureFlag.Name
                        Description     = $FeatureFlag.Description
                        AllowUserToggle = $FeatureFlag.AllowUserToggle
                        Timers          = $FeatureFlag.Timers
                        Endpoints       = $FeatureFlag.Endpoints
                        Pages           = $FeatureFlag.Pages
                        Enabled         = $FeatureFlag.Enabled
                    }
                }
            }
            return $Results
        }
    } catch {
        $ErrorMsg = if ($Id) { "'$Id'" } else { 'flags' }
        Write-Error "Error retrieving feature $($ErrorMsg): $($_.Exception.Message)"
        return $null
    }
}
