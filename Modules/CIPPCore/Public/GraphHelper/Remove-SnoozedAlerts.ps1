function Remove-SnoozedAlerts {
    <#
    .SYNOPSIS
        Filter out snoozed alert items from an alert data array.
    .DESCRIPTION
        Queries the AlertSnooze table for active snooze records matching the given
        cmdlet and tenant, then removes matching items from the data array.
        Also performs lazy cleanup of snoozes expired more than 30 days ago.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,

        [Parameter(Mandatory = $true)]
        [string]$CmdletName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'

    # Query all snooze records for this cmdlet + tenant
    try {
        $SnoozeRecords = Get-CIPPAzDataTableEntity @SnoozeTable -Filter "PartitionKey eq '$($CmdletName)'" | Where-Object {
            $_.Tenant -eq $TenantFilter
        }
    } catch {
        Write-Information "Failed to query AlertSnooze table: $($_.Exception.Message). Returning all data."
        return $Data
    }

    if (-not $SnoozeRecords -or @($SnoozeRecords).Count -eq 0) {
        return $Data
    }

    $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    $ThirtyDaysAgo = $CurrentUnixTime - (30 * 86400)

    # Separate active snoozes from expired ones
    $ActiveHashes = [System.Collections.Generic.HashSet[string]]::new()
    $RecordsToCleanup = [System.Collections.Generic.List[object]]::new()

    foreach ($record in @($SnoozeRecords)) {
        $SnoozeUntil = [int64]$record.SnoozeUntil

        if ($SnoozeUntil -eq -1) {
            # Forever snooze - always active
            $null = $ActiveHashes.Add($record.ContentHash)
        } elseif ($SnoozeUntil -gt $CurrentUnixTime) {
            # Not yet expired
            $null = $ActiveHashes.Add($record.ContentHash)
        } elseif ($SnoozeUntil -lt $ThirtyDaysAgo) {
            # Expired more than 30 days ago - schedule for cleanup
            $RecordsToCleanup.Add($record)
        }
        # Expired but within 30 days - just skip (don't filter, don't cleanup yet)
    }

    # Lazy cleanup of old expired snoozes
    if ($RecordsToCleanup.Count -gt 0) {
        try {
            foreach ($staleRecord in $RecordsToCleanup) {
                Remove-AzDataTableEntity @SnoozeTable -Entity @{
                    PartitionKey = $staleRecord.PartitionKey
                    RowKey       = $staleRecord.RowKey
                    ETag         = '*'
                } | Out-Null
            }
            Write-Information "Cleaned up $($RecordsToCleanup.Count) expired snooze records for $CmdletName / $TenantFilter"
        } catch {
            Write-Information "Failed to cleanup expired snooze records: $($_.Exception.Message)"
        }
    }

    if ($ActiveHashes.Count -eq 0) {
        return $Data
    }

    # Filter out snoozed items
    $FilteredData = foreach ($item in @($Data)) {
        $HashResult = Get-AlertContentHash -AlertItem $item
        if (-not $ActiveHashes.Contains($HashResult.ContentHash)) {
            $item
        } else {
            Write-Information "Snoozing alert item: $($HashResult.ContentPreview) for $CmdletName / $TenantFilter"
        }
    }

    return $FilteredData
}
