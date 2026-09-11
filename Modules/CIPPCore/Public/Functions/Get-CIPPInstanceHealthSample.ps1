function Get-CIPPInstanceHealthSample {
    <#
    .SYNOPSIS
        Reduces a window of container log lines into a single instance-health sample.
    .DESCRIPTION
        Counts the failure signatures that matter for self diagnostics (out-of-memory kills,
        watchdog restarts, HTTP pool exhaustion, stalled orchestrator runs) and extracts the
        peak heap sample, the worst limiter wait, the slowest endpoints and the API clients
        seen in the window.

        Pure text reduction with no I/O, so the timer that calls it can never fail on this
        step and the thresholds stay unit-testable.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPInstanceHealthSample -Lines ([Craft.Services.LogBridge]::GetLogsSince($From, $null, $null, $null))
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $OomCount = 0
    $WatchdogCount = 0
    $PoolExhaustedCount = 0
    $ErrCount = 0
    $StalledRunCount = 0
    $MaxLimiterWaitMs = 0
    $HeapMb = $null
    $EgressRejectCount = 0
    # Ordered HashSet-backed dedup - same client can be rejected many times per window.
    $EgressRejectClients = [System.Collections.Generic.List[string]]::new()
    $EgressRejectClientsSeen = [System.Collections.Generic.HashSet[string]]::new()

    $Endpoints = @{}
    # Keyed on AppId - the same client can appear under several IPs, the last one wins.
    $Clients = [ordered]@{}

    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }

        if ($Line -match 'OutOfMemoryException') { $OomCount++ }
        if ($Line -match 'Container startup attempt|Restart counter') { $WatchdogCount++ }
        if ($Line -match 'HTTP pool exhausted') { $PoolExhaustedCount++ }
        if ($Line -match '\[ERR\]') { $ErrCount++ }
        if ($Line -match 'T\+([0-9]{2,})\.[0-9]+min: .* 0 running ([1-9][0-9]*) pending') { $StalledRunCount++ }

        if ($Line -match 'Egress cap reached') {
            $EgressRejectCount++
            if ($Line -match '429 for (\S+) on' -and $EgressRejectClientsSeen.Add($Matches[1])) {
                $EgressRejectClients.Add($Matches[1])
            }
        }

        if ($Line -match 'Limiter slot acquired after (\d+)ms') {
            $Wait = [int]$Matches[1]
            if ($Wait -gt $MaxLimiterWaitMs) { $MaxLimiterWaitMs = $Wait }
        }

        if ($Line -match 'heap=([0-9]+)MB') {
            $Heap = [int]$Matches[1]
            if ($null -eq $HeapMb -or $Heap -gt $HeapMb) { $HeapMb = $Heap }
        }

        if ($Line -match '\[HTTP\]\s+\S+\s+(\S+)\s+\d{3}\s+(\d+)ms') {
            $Function = $Matches[1]
            $Ms = [int]$Matches[2]
            $Endpoints[$Function] = [int]($Endpoints[$Function]) + $Ms
        }

        # Access checks run more than once per request, so count unique request ids per
        # client rather than lines. Lines without an id fall back to one count each.
        if ($Line -match 'API Access: AppName=([^,]+), AppId=(\S+), IP=([0-9a-fA-F.:]*)') {
            $AppName = $Matches[1]
            $AppId = $Matches[2]
            $IP = $Matches[3]
            $RequestId = if ($Line -match '\[API\]\s+(\S+)\s+PS\b') { $Matches[1] } else { [guid]::NewGuid().ToString() }
            if (-not $Clients.Contains($AppId)) {
                $Clients[$AppId] = @{
                    AppId    = $AppId
                    AppName  = $AppName
                    IP       = $IP
                    Count    = 0
                    Requests = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            if ($Clients[$AppId].Requests.Add($RequestId)) { $Clients[$AppId].Count++ }
            $Clients[$AppId].IP = $IP
            $Clients[$AppId].AppName = $AppName
        }
    }

    $TopEndpoints = @{}
    foreach ($Entry in ($Endpoints.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 3)) {
        $TopEndpoints[$Entry.Key] = $Entry.Value
    }

    $ClientList = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($Client in $Clients.Values) {
        $ClientList.Add(@{ AppId = $Client.AppId; AppName = $Client.AppName; IP = $Client.IP; Count = $Client.Count })
    }

    return [PSCustomObject]@{
        OomCount           = $OomCount
        WatchdogCount      = $WatchdogCount
        PoolExhaustedCount = $PoolExhaustedCount
        ErrCount           = $ErrCount
        MaxLimiterWaitMs   = $MaxLimiterWaitMs
        HeapMb             = $HeapMb
        StalledRunCount    = $StalledRunCount
        TopEndpointsMs     = $TopEndpoints
        Clients            = $ClientList
        EgressRejectCount  = $EgressRejectCount
        EgressRejectClients = $EgressRejectClients
    }
}
