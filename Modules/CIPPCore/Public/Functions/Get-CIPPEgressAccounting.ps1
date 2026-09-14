function Get-CIPPEgressAccounting {
    <#
    .SYNOPSIS
        Reads Craft's per-API-client egress accounting table.
    .DESCRIPTION
        Craft writes 15 minute bucket rows and daily rollups, partitioned per API client plus an
        'instance-total' partition. Requests are counted at the wire, so they include responses
        Craft served from its cache, and only API-client traffic is counted - never the UI.

        The table only exists when egress accounting is enabled, so a missing table or an empty
        result is "no data" ($null), never an error. Never throws.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPEgressAccounting -Hours 24
    #>
    [CmdletBinding()]
    param(
        [int]$Hours = 24,
        [DateTime]$Now = [DateTime]::UtcNow
    )

    try {
        $TableName = if ($env:CRAFT_API_EGRESS_TABLE) { $env:CRAFT_API_EGRESS_TABLE } else { 'CraftEgressAccounting' }
        $Table = Get-CIPPTable -TableName $TableName

        $WindowStart = $Now.AddHours(-$Hours)
        $WindowStart = $WindowStart.AddMinutes(-($WindowStart.Minute % 15)).AddSeconds(-$WindowStart.Second).AddMilliseconds(-$WindowStart.Millisecond)
        $StartKey = 'bkt_{0}' -f $WindowStart.ToString('yyyyMMdd\THHmmss\Z')

        # 'bku_' sorts immediately after every 'bkt_' row, so the window stays a RowKey range scan
        # across the handful of client partitions.
        $BucketRows = @(Get-CIPPAzDataTableEntity @Table -Filter "RowKey ge '$StartKey' and RowKey lt 'bku_'")
        $DayRows = @(Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'day_$($Now.ToString('yyyyMMdd'))'")

        if ($BucketRows.Count -eq 0 -and $DayRows.Count -eq 0) { return $null }

        # One lookup for every AppId in the table - the accounting rows only carry the GUID.
        $AppNames = @{}
        try {
            foreach ($Client in @(Get-CippApiClient)) {
                $ClientId = if ($Client.ClientId) { [string]$Client.ClientId } else { [string]$Client.RowKey }
                if ($ClientId -and $Client.AppName) { $AppNames[$ClientId] = [string]$Client.AppName }
            }
        } catch {
            Write-Information "[InstanceHealth] Could not resolve API client names: $($_.Exception.Message)"
        }

        $InstanceDay = $DayRows | Where-Object { $_.PartitionKey -eq 'instance-total' } | Select-Object -First 1

        $Clients = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Row in ($DayRows | Where-Object { $_.PartitionKey -ne 'instance-total' } | Sort-Object -Property { [long]$_.Bytes } -Descending)) {
            $AppId = [string]$Row.PartitionKey
            $Clients.Add(@{
                    AppId    = $AppId
                    AppName  = if ($AppNames[$AppId]) { $AppNames[$AppId] } else { $AppId }
                    Bytes    = [long]$Row.Bytes
                    Requests = [long]$Row.Requests
                    Shed     = [long]$Row.Shed
                })
        }

        $ByBucket = [ordered]@{}
        foreach ($Row in ($BucketRows | Sort-Object -Property RowKey)) {
            $Key = [string]$Row.RowKey
            if (-not $ByBucket.Contains($Key)) { $ByBucket[$Key] = [System.Collections.Generic.List[object]]::new() }
            $ByBucket[$Key].Add($Row)
        }

        $Buckets = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Key in $ByBucket.Keys) {
            $Rows = $ByBucket[$Key]
            $Total = $Rows | Where-Object { $_.PartitionKey -eq 'instance-total' } | Select-Object -First 1

            $BucketClients = [System.Collections.Generic.List[hashtable]]::new()
            $SumBytes = [long]0
            $SumRequests = [long]0
            $SumShed = [long]0
            foreach ($Row in ($Rows | Where-Object { $_.PartitionKey -ne 'instance-total' })) {
                $AppId = [string]$Row.PartitionKey
                $SumBytes += [long]$Row.Bytes
                $SumRequests += [long]$Row.Requests
                $SumShed += [long]$Row.Shed
                $BucketClients.Add(@{
                        AppId    = $AppId
                        AppName  = if ($AppNames[$AppId]) { $AppNames[$AppId] } else { $AppId }
                        Bytes    = [long]$Row.Bytes
                        Requests = [long]$Row.Requests
                        Shed     = [long]$Row.Shed
                    })
            }

            $Reference = if ($Total) { $Total } else { $Rows[0] }
            $BucketStart = if ($Reference.BucketStartUtc) {
                ([DateTimeOffset]$Reference.BucketStartUtc).UtcDateTime.ToString('yyyy-MM-dd\THH:mm:ss\Z')
            } else {
                # RowKey is the bucket start, so it stands in when the property is absent.
                $Key -replace '^bkt_', ''
            }

            $Buckets.Add(@{
                    BucketStart = $BucketStart
                    Bytes       = if ($Total) { [long]$Total.Bytes } else { $SumBytes }
                    Requests    = if ($Total) { [long]$Total.Requests } else { $SumRequests }
                    Shed        = if ($Total) { [long]$Total.Shed } else { $SumShed }
                    Clients     = @($BucketClients)
                })
        }

        return [pscustomobject]@{
            BucketMinutes = 15
            CapBytes      = if ($InstanceDay) { [long]$InstanceDay.CapBytes } else { [long]0 }
            Enforcing     = if ($InstanceDay) { [bool]$InstanceDay.Enforcing } else { $false }
            TodayBytes    = if ($InstanceDay) { [long]$InstanceDay.Bytes } else { [long]0 }
            TodayRequests = if ($InstanceDay) { [long]$InstanceDay.Requests } else { [long]0 }
            TodayShed     = if ($InstanceDay) { [long]$InstanceDay.Shed } else { [long]0 }
            CapReachedUtc = if ($InstanceDay -and $InstanceDay.CapReachedUtc) { ([DateTimeOffset]$InstanceDay.CapReachedUtc).UtcDateTime.ToString('yyyy-MM-dd\THH:mm:ss\Z') } else { $null }
            Buckets       = @($Buckets)
            Clients       = @($Clients)
        }
    } catch {
        Write-Information "[InstanceHealth] Egress accounting unavailable: $($_.Exception.Message)"
        return $null
    }
}
