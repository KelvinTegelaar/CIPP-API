function Get-CIPPActiveAlertSnoozes {
    <#
    .SYNOPSIS
        Return the active snooze records for one alert cmdlet in one tenant, keyed by content hash.
    .DESCRIPTION
        Reads the AlertSnooze table for the cmdlet and tenant, keeps the snoozes that are still in
        effect (forever, or not yet expired) and returns them as a hashtable of ContentHash to
        snooze record. Snoozes that expired more than 30 days ago are removed while we are here,
        so the table does not grow without bound.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CmdletName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Active = @{}
    $SnoozeTable = Get-CIPPTable -tablename 'AlertSnooze'

    try {
        $SafeCmdlet = ConvertTo-CIPPODataFilterValue -Value $CmdletName -Type String
        $SnoozeRecords = Get-CIPPAzDataTableEntity @SnoozeTable -Filter "PartitionKey eq '$SafeCmdlet'" | Where-Object {
            $_.Tenant -eq $TenantFilter
        }
    } catch {
        Write-Information "Failed to query AlertSnooze table: $($_.Exception.Message). Treating nothing as snoozed."
        return $Active
    }

    if (-not $SnoozeRecords) { return $Active }

    $CurrentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    $ThirtyDaysAgo = $CurrentUnixTime - (30 * 86400)
    $RecordsToCleanup = [System.Collections.Generic.List[object]]::new()

    foreach ($Record in @($SnoozeRecords)) {
        $SnoozeUntil = [int64]$Record.SnoozeUntil
        if ($SnoozeUntil -eq -1 -or $SnoozeUntil -gt $CurrentUnixTime) {
            $Active[[string]$Record.ContentHash] = $Record
        } elseif ($SnoozeUntil -lt $ThirtyDaysAgo) {
            $RecordsToCleanup.Add($Record)
        }
    }

    if ($RecordsToCleanup.Count -gt 0) {
        try {
            foreach ($Stale in $RecordsToCleanup) {
                Remove-CIPPAzDataTableEntity @SnoozeTable -Entity @{
                    PartitionKey = $Stale.PartitionKey
                    RowKey       = $Stale.RowKey
                    ETag         = '*'
                } | Out-Null
            }
            Write-Information "Cleaned up $($RecordsToCleanup.Count) expired snooze records for $CmdletName / $TenantFilter"
        } catch {
            Write-Information "Failed to clean up expired snooze records: $($_.Exception.Message)"
        }
    }

    return $Active
}
