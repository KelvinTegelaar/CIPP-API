function Test-CIPPRerun {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Type,
        $API,
        $Settings,
        $Headers,
        [switch]$Clear,
        [switch]$ClearAll,
        [int64]$Interval = 0,  # Custom interval in seconds (for scheduled tasks)
        [int64]$BaseTime = 0   # Base time to calculate from (defaults to current time)
    )
    $RerunTable = Get-CIPPTable -tablename 'RerunCache'

    # Use custom interval if provided, otherwise use type-based defaults
    if ($Interval -gt 0) {
        $EstimatedDifference = $Interval
    } else {
        $EstimatedDifference = switch ($Type) {
            'Standard' { 9800 } # 2 hours 45 minutes ish.
            'BPA' { 85000 } # 24 hours ish.
            'CippTests' { 85000 } # 24 hours ish.
            default { throw "Unknown type: $Type" }
        }
    }

    # Use BaseTime if provided, otherwise use current time
    $CurrentUnixTime = if ($BaseTime -gt 0) { $BaseTime } else { [int][double]::Parse((Get-Date -UFormat %s)) }
    $EstimatedNextRun = $CurrentUnixTime + $EstimatedDifference

    try {
        $RerunData = Get-CIPPAzDataTableEntity @RerunTable -filter "PartitionKey eq '$($TenantFilter)'" | Where-Object { $_.RowKey -match "^$($Type)_$($API)" }
        if ($ClearAll.IsPresent) {
            $AllRerunData = Get-CIPPAzDataTableEntity @RerunTable
            if ($AllRerunData) {
                Write-Information "Clearing all rerun cache entries for $($Type)_$($API)"
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
