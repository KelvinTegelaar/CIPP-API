function Write-AlertTrace {
    <#
    .FUNCTIONALITY
    Internal function. Pleases most of Write-AlertTrace for alerting purposes
    #>
    param(
        $cmdletName,
        $data,
        $tenantFilter,
        [string]$PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString(),
        [string]$AlertComment = $null
    )
    # Filter out snoozed alert items before comparison and storage
    $data = @(Remove-SnoozedAlerts -Data $data -CmdletName $cmdletName -TenantFilter $tenantFilter)
    if (-not $data -or $data.Count -eq 0) {
        Write-Host "All alert items are snoozed for cmdlet '$cmdletName' and tenant '$tenantFilter'. Skipping alert trace." -ForegroundColor Yellow
        return $null
    }

    $Table = Get-CIPPTable -tablename AlertLastRun
    $Row = Get-CIPPAzDataTableEntity @table -Filter "RowKey eq '$($tenantFilter)-$($cmdletName)' and PartitionKey eq '$PartitionKey'"
    $LogData = ConvertTo-Json -InputObject $data -Compress -Depth 10 | Out-String
    $Changed = $true
    if ($Row) {
        try {
            $Changed = [bool](Compare-Object $Row.LogData $LogData)
        } catch {
            $Changed = $true
        }
        Write-Host "Comparing new alert data with existing data for cmdlet '$cmdletName' and tenant '$tenantFilter'. Changed: $Changed"
    }

    # Written on every run with active items: LastSeen tells the scheduler the alert is
    # still firing even when the data is unchanged, so it can clear resolved alerts.
    $TableRow = @{
        'PartitionKey' = $PartitionKey
        'RowKey'       = "$($tenantFilter)-$($cmdletName)"
        'CmdletName'   = "$cmdletName"
        'Tenant'       = "$tenantFilter"
        'LogData'      = [string]$LogData
        'AlertComment' = [string]$AlertComment
        'LastSeen'     = [string][int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    }
    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table -Force | Out-Null

    # Only changed data is returned: the caller's output drives notifications, and an
    # unchanged persisting condition must not re-notify on every run (alerts can recur
    # every 30 minutes, and the fixed-partition alerts keep one row across days).
    if ($Changed) {
        return $data
    }
}
