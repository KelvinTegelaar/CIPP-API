function Start-InstanceHealthSample {
    <#
    .SYNOPSIS
    Timer function that records a 5 minute instance-health sample
    .DESCRIPTION
    Reduces the last five minutes of container log lines into one bucket row in the
    InstanceHealth table, plus one row per API client seen in that window. The diagnostics
    endpoint reads these rows instead of rescanning the log, so a self-diagnostics run stays
    cheap and can look further back than the retained log files.

    The log bridge only exists inside the container host, so a missing bridge is logged and
    skipped rather than failing the timer.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('Start-InstanceHealthSample', 'Record instance health sample')) { return }

    $Now = [DateTime]::UtcNow
    # Bucket on the 5 minute floor so samples line up across restarts and nodes.
    $Bucket = $Now.AddMinutes(-($Now.Minute % 5)).ToString('yyyy-MM-ddTHH:mm')

    try {
        $Lines = [Craft.Services.LogBridge]::GetLogsSince($Now.AddMinutes(-5), $null, $null, $null)
    } catch {
        Write-Information "[InstanceHealth] Log bridge unavailable, skipping sample: $($_.Exception.Message)"
        return
    }

    try {
        $Sample = Get-CIPPInstanceHealthSample -Lines @($Lines)

        # Live memory reading from the stats history, used as a floor when the log carried no
        # heap sample. The reported GC limit is the real ceiling for the headroom check.
        $HeapMbLive = $null
        $GcHeapLimitMb = $null
        try {
            $Point = @([Craft.Services.StatsHistoryBridge]::GetHistory(5, 1)) | Select-Object -Last 1
            if ($Point) {
                $HeapMbLive = [int][math]::Round([double]$Point.HeapMB)
                if ([double]$Point.GCHeapLimitMB -gt 0) { $GcHeapLimitMb = [int][math]::Round([double]$Point.GCHeapLimitMB) }
            }
        } catch {
            Write-Information "[InstanceHealth] Stats history unavailable: $($_.Exception.Message)"
        }

        $Table = Get-CIPPTable -TableName 'InstanceHealth'

        # One fixed partition for the whole table so a window read is a single partition-scoped
        # RowKey range instead of a cross-partition scan; the bucket lives in RowKey and Bucket.
        $Entity = @{
            PartitionKey       = 'InstanceHealth'
            RowKey             = "${Bucket}_sample"
            Bucket             = $Bucket
            Kind               = 'sample'
            OomCount           = [int]$Sample.OomCount
            WatchdogCount      = [int]$Sample.WatchdogCount
            PoolExhaustedCount = [int]$Sample.PoolExhaustedCount
            ErrCount           = [int]$Sample.ErrCount
            MaxLimiterWaitMs   = [int]$Sample.MaxLimiterWaitMs
            StalledRunCount    = [int]$Sample.StalledRunCount
            TopEndpointsMs     = [string]($Sample.TopEndpointsMs | ConvertTo-Json -Compress)
        }
        # Nullable readings are omitted rather than stored as a sentinel, so "no reading" and
        # "read zero" stay distinguishable.
        if ($null -ne $Sample.HeapMb) { $Entity.HeapMb = [int]$Sample.HeapMb }
        if ($null -ne $HeapMbLive) { $Entity.HeapMbLive = [int]$HeapMbLive }
        if ($null -ne $GcHeapLimitMb) { $Entity.GcHeapLimitMb = [int]$GcHeapLimitMb }

        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

        foreach ($Client in $Sample.Clients) {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'InstanceHealth'
                RowKey       = "${Bucket}_client_$($Client.AppId)"
                Bucket       = $Bucket
                Kind         = 'client'
                AppId        = [string]$Client.AppId
                AppName      = [string]$Client.AppName
                IP           = [string]$Client.IP
                Count        = [int]$Client.Count
            } -Force | Out-Null
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'InstanceHealthSample' -message "Failed to record instance health sample: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
