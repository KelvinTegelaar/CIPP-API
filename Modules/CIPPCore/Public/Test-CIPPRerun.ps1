function Test-CIPPRerun {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Type,
        $API,
        $Settings,
        $Headers,
        [int]$RunIntervalHours,
        [switch]$Clear,
        [switch]$ClearAll
    )
    
    # Default rerun intervals in seconds (slightly under full hours to account for Azure timer drift)
    $StandardDefaultSeconds = 9800              # ~2 hours 43 minutes (slightly under 3 hour timer)
    $BPADefaultSeconds = 85000                  # ~23 hours 36 minutes (slightly under 24 hour timer)
    $MinimumIntervalHours = 3                   # Minimum allowed custom interval (must be multiple of 3)
    $TimerDriftCompensationSeconds = 900        # ~15 minutes subtracted once for Azure timer drift
    
    $RerunTable = Get-CIPPTable -tablename 'RerunCache'
    # Check if a custom run interval is provided (in hours)
    # Enforce minimum interval of 3 hours (must be multiple of 3), calculate seconds slightly under the full interval
    if ($RunIntervalHours -ge $MinimumIntervalHours) {
        # Subtract timer drift compensation once to account for Azure timer drift
        $EstimatedDifference = ($RunIntervalHours * 3600) - $TimerDriftCompensationSeconds
    } else {
        $EstimatedDifference = switch ($Type) {
            'Standard' { $StandardDefaultSeconds }
            'BPA' { $BPADefaultSeconds }
            default { throw "Unknown type: $Type" }
        }
    }
    $CurrentUnixTime = [int][double]::Parse((Get-Date -UFormat %s))
    $EstimatedNextRun = $CurrentUnixTime + $EstimatedDifference

    try {
        $RerunData = Get-CIPPAzDataTableEntity @RerunTable -filter "PartitionKey eq '$($TenantFilter)' and RowKey eq '$($Type)_$($API)'"
        if ($ClearAll.IsPresent) {
            $AllRerunData = Get-CIPPAzDataTableEntity @RerunTable
            if ($AllRerunData) {
                Remove-AzDataTableEntity @RerunTable -Entity $AllRerunData -Force
            }
            return $false
        }

        if ($Clear.IsPresent) {
            if ($RerunData) {
                Remove-AzDataTableEntity @RerunTable -Entity $RerunData
            }
            return $false
        } elseif ($RerunData) {
            if ($Settings -and $RerunData.Settings) {
                Write-Host 'Testing rerun settings'
                $PreviousSettings = $RerunData.Settings
                $NewSettings = $($Settings | ConvertTo-Json -Depth 10 -Compress)
                if ($NewSettings.Length -ne $PreviousSettings.Length) {
                    Write-Host "$($NewSettings.Length) vs $($PreviousSettings.Length) - settings have changed."
                    $RerunData.EstimatedNextRun = $EstimatedNextRun
                    $RerunData.Settings = "$($Settings | ConvertTo-Json -Depth 10 -Compress)"
                    Add-CIPPAzDataTableEntity @RerunTable -Entity $RerunData -Force
                    return $false # Not a rerun because settings have changed.
                }
            }
            if ($RerunData.EstimatedNextRun -gt $CurrentUnixTime) {
                Write-LogMessage -API $API -message "Standard rerun detected for $($API). Prevented from running again." -tenant $TenantFilter -headers $Headers -Sev 'Info'
                return $true
            } else {
                $RerunData.EstimatedNextRun = $EstimatedNextRun
                $RerunData.Settings = "$($Settings | ConvertTo-Json -Depth 10 -Compress)"
                Add-CIPPAzDataTableEntity @RerunTable -Entity $RerunData -Force
                return $false
            }
        } else {
            $EstimatedNextRun = $CurrentUnixTime + $EstimatedDifference
            $NewEntity = @{
                PartitionKey     = "$TenantFilter"
                RowKey           = "$($Type)_$($API)"
                Settings         = "$($Settings | ConvertTo-Json -Depth 10 -Compress)"
                EstimatedNextRun = $EstimatedNextRun
            }
            Add-CIPPAzDataTableEntity @RerunTable -Entity $NewEntity -Force
            return $false
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Could not detect if this is a rerun: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $API -message "Could not detect if this is a rerun: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        return $false
    }
}
