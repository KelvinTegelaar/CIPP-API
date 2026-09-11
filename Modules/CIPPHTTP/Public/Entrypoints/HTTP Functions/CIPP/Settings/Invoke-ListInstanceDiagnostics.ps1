function Invoke-ListInstanceDiagnostics {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    .DESCRIPTION
        Self diagnostics for this instance. Checks turns the recorded InstanceHealth samples
        into a pass/warn/fail list with a suggested fix per finding; Timeline returns the raw
        buckets plus the restart and out-of-memory events, with the API clients that were
        busiest in the hour leading up to each event. Requires SuperAdmin access.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = $Request.Query.Action ?? 'Checks'

    $Hours = 24
    if ($Request.Query.Hours) { $Hours = [int]$Request.Query.Hours }
    if ($Hours -lt 1) { $Hours = 1 }
    if ($Hours -gt 336) { $Hours = 336 }

    $BucketFormat = 'yyyy-MM-ddTHH:mm'
    $BucketStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal

    function ConvertFrom-HealthBucket {
        param([string]$Bucket)
        return [DateTime]::ParseExact($Bucket, $BucketFormat, [cultureinfo]::InvariantCulture, $BucketStyles)
    }

    # Heap ceiling comes from the limit the runtime reported on the newest sample, then the GC
    # hard limit the host set (hex bytes), then the default budget. Shared by Checks and Timeline
    # so both report the same cap.
    function Get-DiagnosticsHeapCapMb {
        param($Samples)
        $HeapCapMb = 2398
        if ($env:DOTNET_GCHeapHardLimit) {
            try { $HeapCapMb = [int]([Convert]::ToInt64(($env:DOTNET_GCHeapHardLimit -replace '^0x', ''), 16) / 1MB) } catch { $HeapCapMb = 2398 }
        }
        $ReportedCap = @($Samples | Where-Object { [int]$_.GcHeapLimitMb -gt 0 }) | Select-Object -Last 1
        if ($ReportedCap) { $HeapCapMb = [int]$ReportedCap.GcHeapLimitMb }
        return $HeapCapMb
    }

    function Format-DiagnosticsBytes {
        param([long]$Bytes)
        if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
        return '{0:N1} MB' -f ($Bytes / 1MB)
    }

    try {
        $Now = [DateTime]::UtcNow
        $WindowStart = $Now.AddHours(-$Hours)
        $StartBucket = $WindowStart.AddMinutes(-($WindowStart.Minute % 5)).ToString($BucketFormat)

        # One fixed partition, so this is a single partition-scoped RowKey range instead of a
        # cross-partition scan.
        $Table = Get-CIPPTable -TableName 'InstanceHealth'
        $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'InstanceHealth' and RowKey ge '$StartBucket'")

        $Samples = @($Rows | Where-Object { $_.Kind -eq 'sample' } | Sort-Object -Property Bucket)
        $Boots = @($Rows | Where-Object { $_.Kind -eq 'boot' } | Sort-Object -Property Bucket)
        $ClientRows = @($Rows | Where-Object { $_.Kind -eq 'client' })

        # AppId -> totals over the whole window, used for both the client check and the
        # per-event baselines.
        $ClientTotals = @{}
        foreach ($Row in $ClientRows) {
            $AppId = [string]$Row.AppId
            if (-not $ClientTotals.ContainsKey($AppId)) {
                $ClientTotals[$AppId] = @{ AppId = $AppId; AppName = [string]$Row.AppName; IP = [string]$Row.IP; Count = 0 }
            }
            $ClientTotals[$AppId].Count += [int]$Row.Count
            if ($Row.AppName) { $ClientTotals[$AppId].AppName = [string]$Row.AppName }
            if ($Row.IP) { $ClientTotals[$AppId].IP = [string]$Row.IP }
        }

        switch ($Action) {
            'Checks' {
                $Results = [System.Collections.Generic.List[hashtable]]::new()

                $OomTotal = ($Samples | Measure-Object -Property OomCount -Sum).Sum ?? 0
                $Results.Add(@{
                        Check  = 'oom'
                        Status = if ($OomTotal -gt 0) { 'FAIL' } else { 'PASS' }
                        Detail = if ($OomTotal -gt 0) { "$OomTotal OutOfMemoryException(s) in the last ${Hours}h" } else { "No out-of-memory errors in the last ${Hours}h" }
                        Fix    = if ($OomTotal -gt 0) { 'Move to a larger plan or reduce concurrent background work - the process is hitting its heap limit.' } else { $null }
                    })

                $HeapCapMb = Get-DiagnosticsHeapCapMb -Samples $Samples

                # A window can hold live-only samples, so fall back to the live reading rather
                # than reporting no data at all.
                $PeakHeap = ($Samples | ForEach-Object { if ($null -ne $_.HeapMb) { [int]$_.HeapMb } elseif ($null -ne $_.HeapMbLive) { [int]$_.HeapMbLive } } | Measure-Object -Maximum).Maximum
                if ($null -eq $PeakHeap -or $HeapCapMb -le 0) {
                    $Results.Add(@{ Check = 'heap-headroom'; Status = 'INFO'; Detail = 'No heap samples recorded in this window'; Fix = $null })
                } else {
                    $Percent = [math]::Round(($PeakHeap / $HeapCapMb) * 100, 1)
                    $HeapDetail = "Peak heap ${PeakHeap}MB of ${HeapCapMb}MB ($Percent%)"
                    if ($Percent -gt 100) {
                        # A single log window can straddle two containers, so a peak above the
                        # cap is a swap artefact rather than a real over-allocation.
                        $Results.Add(@{ Check = 'heap-headroom'; Status = 'WARN'; Detail = "$HeapDetail - log spans two containers (image swap)"; Fix = 'Re-check after the next full window on a single container.' })
                    } elseif ($Percent -ge 90) {
                        $Results.Add(@{ Check = 'heap-headroom'; Status = 'FAIL'; Detail = $HeapDetail; Fix = 'Move to a larger plan - the instance is one burst away from an out-of-memory restart.' })
                    } elseif ($Percent -ge 75) {
                        $Results.Add(@{ Check = 'heap-headroom'; Status = 'WARN'; Detail = $HeapDetail; Fix = 'Watch this - consider a larger plan or fewer concurrent scheduled tasks.' })
                    } else {
                        $Results.Add(@{ Check = 'heap-headroom'; Status = 'PASS'; Detail = $HeapDetail; Fix = $null })
                    }
                }

                $WatchdogTotal = ($Samples | Measure-Object -Property WatchdogCount -Sum).Sum ?? 0
                $Results.Add(@{
                        Check  = 'watchdog'
                        Status = if ($WatchdogTotal -gt 0) { 'WARN' } else { 'PASS' }
                        Detail = if ($WatchdogTotal -gt 0) { "$WatchdogTotal watchdog restart line(s) in the last ${Hours}h" } else { "No watchdog restarts in the last ${Hours}h" }
                        Fix    = if ($WatchdogTotal -gt 0) { 'Check the container log around each restart - the process is failing to stay up.' } else { $null }
                    })

                $PoolTotal = ($Samples | Measure-Object -Property PoolExhaustedCount -Sum).Sum ?? 0
                $Results.Add(@{
                        Check  = 'pool-exhausted'
                        Status = if ($PoolTotal -gt 0) { 'WARN' } else { 'PASS' }
                        Detail = if ($PoolTotal -gt 0) { "HTTP pool exhausted $PoolTotal time(s) in the last ${Hours}h" } else { "HTTP pool never exhausted in the last ${Hours}h" }
                        Fix    = if ($PoolTotal -gt 0) { 'Requests are queuing for a runspace - reduce parallel API clients or move to a larger plan.' } else { $null }
                    })

                $StalledTotal = ($Samples | Measure-Object -Property StalledRunCount -Sum).Sum ?? 0
                $Results.Add(@{
                        Check  = 'stalled-runs'
                        Status = if ($StalledTotal -gt 0) { 'WARN' } else { 'PASS' }
                        Detail = if ($StalledTotal -gt 0) { "$StalledTotal stalled orchestrator run report(s) in the last ${Hours}h" } else { "No stalled orchestrator runs in the last ${Hours}h" }
                        Fix    = if ($StalledTotal -gt 0) { 'Runs have pending work but nothing running - cancel the stuck run from Worker Health and let it re-queue.' } else { $null }
                    })

                $EgressSamples = @($Samples | Where-Object { $null -ne $_.EgressBytesToday })
                if ($EgressSamples.Count -eq 0) {
                    $Results.Add(@{ Check = 'egress'; Status = 'INFO'; Detail = 'No API egress recorded in this window - egress accounting is off or no API client traffic was served'; Fix = $null })
                } else {
                    $NewestEgress = $EgressSamples | Sort-Object -Property Bucket | Select-Object -Last 1
                    $TodayBytes = [long]$NewestEgress.EgressBytesToday
                    $CapSample = @($Samples | Where-Object { [long]$_.EgressCapBytes -gt 0 }) | Select-Object -Last 1
                    $CapBytes = if ($CapSample) { [long]$CapSample.EgressCapBytes } else { $null }
                    $EgressRejectTotal = ($Samples | Measure-Object -Property EgressRejectCount -Sum).Sum ?? 0

                    if ($EgressRejectTotal -gt 0) {
                        # Distinct client names across the window's reject lists, in first-seen order.
                        $RejectClients = [System.Collections.Generic.List[string]]::new()
                        $Seen = [System.Collections.Generic.HashSet[string]]::new()
                        foreach ($RejectSample in ($Samples | Where-Object { $_.EgressRejectClients })) {
                            try {
                                foreach ($ClientName in @($RejectSample.EgressRejectClients | ConvertFrom-Json)) {
                                    if ($Seen.Add($ClientName)) { $RejectClients.Add($ClientName) }
                                }
                            } catch {}
                        }
                        $CapDisplay = if ($CapBytes) { Format-DiagnosticsBytes -Bytes $CapBytes } else { 'unknown' }
                        $Results.Add(@{
                                Check  = 'egress'
                                Status = 'FAIL'
                                Detail = "API egress cap reached: $EgressRejectTotal request(s) rejected with 429, clients: $($RejectClients -join ', '); served $(Format-DiagnosticsBytes -Bytes $TodayBytes) of $CapDisplay"
                                Fix    = 'Identify which integration is pulling the most data and throttle it, or raise the daily egress budget.'
                            })
                    } elseif ($CapBytes) {
                        $Percent = [math]::Round(($TodayBytes / $CapBytes) * 100, 1)
                        $EgressDetail = "Served $(Format-DiagnosticsBytes -Bytes $TodayBytes) of $(Format-DiagnosticsBytes -Bytes $CapBytes) today ($Percent%)"
                        if ($Percent -ge 75) {
                            $Results.Add(@{ Check = 'egress'; Status = 'WARN'; Detail = $EgressDetail; Fix = $null })
                        } else {
                            $Results.Add(@{ Check = 'egress'; Status = 'PASS'; Detail = $EgressDetail; Fix = $null })
                        }
                    } else {
                        $Results.Add(@{ Check = 'egress'; Status = 'INFO'; Detail = "Served $(Format-DiagnosticsBytes -Bytes $TodayBytes) today (no daily budget set)"; Fix = $null })
                    }
                }

                $TotalAccess = 0
                foreach ($Client in $ClientTotals.Values) { $TotalAccess += $Client.Count }
                $TopClient = $ClientTotals.Values | Sort-Object -Property Count -Descending | Select-Object -First 1
                if ($TopClient -and $TotalAccess -gt 0 -and $TopClient.Count -ge 10000 -and ($TopClient.Count / $TotalAccess) -ge 0.5) {
                    $Share = [math]::Round(($TopClient.Count / $TotalAccess) * 100)
                    $Results.Add(@{
                            Check  = 'api-clients'
                            Status = 'WARN'
                            Detail = "API client $($TopClient.AppName) ($($TopClient.IP)) made $($TopClient.Count) of $TotalAccess authenticated API accesses ($Share%)"
                            Fix    = 'A single integration dominates this instance - throttle it or give it its own instance.'
                        })
                } else {
                    $TopDetail = if ($TopClient) { "busiest: $($TopClient.AppName) ($($TopClient.Count))" } else { 'no API clients seen' }
                    $Results.Add(@{
                            Check  = 'api-clients'
                            Status = 'INFO'
                            Detail = "$TotalAccess authenticated API accesses from $($ClientTotals.Count) client(s) in the last ${Hours}h, $TopDetail"
                            Fix    = $null
                        })
                }

                $RestartCount = $Boots.Count
                $Results.Add(@{
                        Check  = 'restarts'
                        Status = if ($RestartCount -gt 2) { 'WARN' } elseif ($RestartCount -ge 1) { 'INFO' } else { 'PASS' }
                        Detail = if ($RestartCount -gt 2) { "Container restarted $RestartCount times in the last ${Hours}h" } elseif ($RestartCount -ge 1) { "Container restarted $RestartCount time(s) in the last ${Hours}h" } else { "No restarts in the last ${Hours}h" }
                        Fix    = if ($RestartCount -gt 2) { 'Repeated restarts usually follow an out-of-memory kill or an auto-update loop - check the timeline.' } else { $null }
                    })

                try {
                    $Runs = @([Craft.Services.WorkerMetricsBridge]::GetRunSummaries())
                    $Stalled = [System.Collections.Generic.List[string]]::new()
                    foreach ($Run in $Runs) {
                        if (Test-CIPPStalledRun -Run $Run -Now $Now) {
                            $Name = [string]$Run.Name
                            $Stalled.Add($(if ($Name) { $Name } else { 'unnamed run' }))
                        }
                    }
                    $Results.Add(@{
                            Check  = 'orchestrator'
                            Status = if ($Stalled.Count -gt 0) { 'FAIL' } else { 'PASS' }
                            Detail = if ($Stalled.Count -gt 0) { "Stalled for over 2h with pending work: $($Stalled -join ', ')" } else { 'No stalled orchestrator runs' }
                            Fix    = if ($Stalled.Count -gt 0) { 'Cancel the run from Worker Health so its work re-queues on the next timer.' } else { $null }
                        })
                } catch {
                    $Results.Add(@{ Check = 'orchestrator'; Status = 'INFO'; Detail = 'Worker metrics not available'; Fix = $null })
                }

                # ARM-only, so it exists on hosted instances and is skipped everywhere else.
                if ($env:WEBSITE_SITE_NAME) {
                    $SiteName = $env:WEBSITE_SITE_NAME
                    $Subscription = $null
                    $RGName = $null
                    try {
                        $Subscription = Get-CIPPAzFunctionAppSubId
                        $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $SiteName
                    } catch {
                        Write-Information "Could not resolve ARM site details: $($_.Exception.Message)"
                    }

                    if ($Subscription -and $RGName) {
                        try {
                            $Uri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/containerlogs?api-version=2023-12-01"
                            $ContainerLog = New-CIPPAzRestRequest -Uri $Uri -Method POST
                            if ($ContainerLog -isnot [string]) { $ContainerLog = [string]$ContainerLog }
                            $Cutoff = $Now.AddHours(-24)
                            $Stopping = 0
                            foreach ($Line in ($ContainerLog -split "`n")) {
                                if ($Line -notmatch 'State:\s*Stopping') { continue }
                                # Undated lines are counted; the endpoint only returns recent log.
                                if ($Line -match '^(\d{4}-\d{2}-\d{2}T[\d:.]+)') {
                                    try { if ([DateTime]::Parse($Matches[1]).ToUniversalTime() -lt $Cutoff) { continue } } catch {}
                                }
                                $Stopping++
                            }
                            $Results.Add(@{
                                    Check  = 'container-log'
                                    Status = if ($Stopping -gt 2) { 'WARN' } else { 'PASS' }
                                    Detail = "$Stopping container stop event(s) in the platform log in the last 24h"
                                    Fix    = if ($Stopping -gt 2) { 'The platform is cycling the container - check the restart and out-of-memory checks above.' } else { $null }
                                })
                        } catch {
                            $Results.Add(@{ Check = 'container-log'; Status = 'INFO'; Detail = 'Platform container log not available'; Fix = $null })
                        }
                    } else {
                        $Results.Add(@{ Check = 'container-log'; Status = 'INFO'; Detail = 'Platform container log not available'; Fix = $null })
                    }
                }

                $Body = @{ Results = @($Results) }
            }
            'Timeline' {
                # Bucket -> AppId -> count, so an event can look back over the preceding hour
                # without re-scanning every row.
                $ClientsByBucket = @{}
                foreach ($Row in $ClientRows) {
                    $Bucket = [string]$Row.Bucket
                    if (-not $ClientsByBucket.ContainsKey($Bucket)) { $ClientsByBucket[$Bucket] = @{} }
                    $AppId = [string]$Row.AppId
                    $ClientsByBucket[$Bucket][$AppId] = [int]$ClientsByBucket[$Bucket][$AppId] + [int]$Row.Count
                }

                $Buckets = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($Sample in $Samples) {
                    $Bucket = [string]$Sample.Bucket
                    $BucketClients = [System.Collections.Generic.List[hashtable]]::new()
                    if ($ClientsByBucket.ContainsKey($Bucket)) {
                        foreach ($Entry in $ClientsByBucket[$Bucket].GetEnumerator()) {
                            $BucketClients.Add(@{
                                    AppId   = $Entry.Key
                                    AppName = [string]$ClientTotals[$Entry.Key].AppName
                                    IP      = [string]$ClientTotals[$Entry.Key].IP
                                    Count   = $Entry.Value
                                })
                        }
                    }
                    $TopEndpoints = @{}
                    if ($Sample.TopEndpointsMs) {
                        try { $TopEndpoints = $Sample.TopEndpointsMs | ConvertFrom-Json -AsHashtable } catch {}
                    }
                    $Buckets.Add(@{
                            Bucket             = $Bucket
                            OomCount           = [int]$Sample.OomCount
                            WatchdogCount      = [int]$Sample.WatchdogCount
                            PoolExhaustedCount = [int]$Sample.PoolExhaustedCount
                            ErrCount           = [int]$Sample.ErrCount
                            MaxLimiterWaitMs   = [int]$Sample.MaxLimiterWaitMs
                            StalledRunCount    = [int]$Sample.StalledRunCount
                            HeapMb             = if ($null -ne $Sample.HeapMb) { [int]$Sample.HeapMb } else { $null }
                            HeapMbLive         = if ($null -ne $Sample.HeapMbLive) { [int]$Sample.HeapMbLive } else { $null }
                            EgressBytes        = if ($null -ne $Sample.EgressBytes) { [long]$Sample.EgressBytes } else { $null }
                            EgressBytesToday   = if ($null -ne $Sample.EgressBytesToday) { [long]$Sample.EgressBytesToday } else { $null }
                            TopEndpointsMs     = $TopEndpoints
                            Clients            = @($BucketClients)
                        })
                }

                # Baseline is per-hour, so an event's 60 minute lead-in compares like for like.
                $WindowHours = [math]::Max($Hours, 1)

                $Events = [System.Collections.Generic.List[hashtable]]::new()
                $EventSources = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($Boot in $Boots) {
                    $EventSources.Add(@{ Bucket = [string]$Boot.Bucket; Type = 'boot'; GapMinutes = if ($null -ne $Boot.GapMinutes) { [int]$Boot.GapMinutes } else { $null } })
                }
                foreach ($Sample in ($Samples | Where-Object { [int]$_.OomCount -gt 0 })) {
                    $EventSources.Add(@{ Bucket = [string]$Sample.Bucket; Type = 'oom'; GapMinutes = $null })
                }

                foreach ($Source in ($EventSources | Sort-Object -Property { $_.Bucket })) {
                    $EventTime = ConvertFrom-HealthBucket -Bucket $Source.Bucket
                    $LeadIn = @{}
                    for ($Offset = 5; $Offset -le 60; $Offset += 5) {
                        $Key = $EventTime.AddMinutes(-$Offset).ToString($BucketFormat)
                        if (-not $ClientsByBucket.ContainsKey($Key)) { continue }
                        foreach ($Entry in $ClientsByBucket[$Key].GetEnumerator()) {
                            $LeadIn[$Entry.Key] = [int]$LeadIn[$Entry.Key] + $Entry.Value
                        }
                    }

                    $TopClients = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($Entry in ($LeadIn.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 3)) {
                        $Baseline = [math]::Round($ClientTotals[$Entry.Key].Count / $WindowHours, 2)
                        $TopClients.Add(@{
                                AppId    = $Entry.Key
                                AppName  = [string]$ClientTotals[$Entry.Key].AppName
                                IP       = [string]$ClientTotals[$Entry.Key].IP
                                Count    = $Entry.Value
                                Baseline = $Baseline
                                Ratio    = if ($Baseline -gt 0) { [math]::Round($Entry.Value / $Baseline, 2) } else { $null }
                            })
                    }

                    $Events.Add(@{
                            Bucket     = $Source.Bucket
                            Type       = $Source.Type
                            GapMinutes = $Source.GapMinutes
                            TopClients = @($TopClients)
                        })
                }

                $EgressCapSample = @($Samples | Where-Object { [long]$_.EgressCapBytes -gt 0 }) | Select-Object -Last 1
                $EgressAvailable = @($Samples | Where-Object { $null -ne $_.EgressBytesToday }).Count -gt 0

                $Body = @{
                    Results = @{
                        Buckets         = @($Buckets)
                        Events          = @($Events)
                        HeapCapMb       = Get-DiagnosticsHeapCapMb -Samples $Samples
                        EgressCapBytes  = if ($EgressCapSample) { [long]$EgressCapSample.EgressCapBytes } else { $null }
                        EgressAvailable = $EgressAvailable
                    }
                }
            }
            default {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Unknown action: $Action" }
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Instance diagnostics error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
