function Invoke-ListApiEgress {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    .DESCRIPTION
        Per-API-client egress usage for this instance against the daily cap. Reads the
        CraftEgressAccounting table that the Craft runtime mirrors its egress accounting into (the same
        storage account, so this reads it directly): a per-day audit row per client plus an instance
        total, and 15-minute buckets for the trend. Returns today's instance summary (used-of-cap,
        enforcing, when the cap was first hit, how many requests were shed), the per-client breakdown,
        the top endpoints by egress (instance-wide and per client), signed-in user traffic (reported,
        never capped), and the last-24h instance trend. When the table has no data for today - accounting off, a
        non-hosted instance, or simply no app-only traffic yet - Enabled is false and the UI hides the
        card. SuperAdmin only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Now = [DateTime]::UtcNow
    $Today = $Now.ToString('yyyyMMdd')
    $DailyKey = "day_$Today"

    # Trend window in hours (default 24). Clamped to the table's 7-day retention.
    $Hours = 24
    if ($Request.Query.Hours) { $Hours = [int]$Request.Query.Hours }
    if ($Hours -lt 1) { $Hours = 1 }
    if ($Hours -gt 168) { $Hours = 168 }

    # 15-minute buckets over the window; the bkt_ prefix range excludes the day_ rows.
    $SinceBucket = 'bkt_{0}' -f $Now.AddHours(-$Hours).ToString('yyyyMMddTHHmmssZ')
    $SystemPartition = 'instance-total'
    $InteractivePartition = 'interactive'

    try {
        $Table = Get-CIPPTable -TableName 'CraftEgressAccounting'

        # Today's daily audit rows (per client + the instance total) - a small cross-partition read.
        $DailyRows = @(Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$DailyKey'")
        $Instance = $DailyRows | Where-Object { $_.PartitionKey -eq $SystemPartition } | Select-Object -First 1

        if (-not $Instance) {
            # No accounting data for today: not enabled here (or nothing served yet).
            $Body = @{
                Results = @{
                    Enabled = $false
                    Hosted  = ($env:CIPP_HOSTED -eq 'true')
                    DateUtc = $Now.ToString('yyyy-MM-dd')
                }
            }
            return [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $Body }
        }

        $CapBytes = [long]($Instance.CapBytes ?? 0)
        $BytesToday = [long]($Instance.Bytes ?? 0)
        $PctOfCap = if ($CapBytes -gt 0) { [math]::Round(($BytesToday / $CapBytes) * 100, 1) } else { $null }

        # Friendly names from the API client registry (fall back to the AppId when unregistered).
        $NameByAppId = @{}
        try {
            $ClientTable = Get-CIPPTable -TableName 'ApiClients'
            foreach ($ClientRow in @(Get-CIPPAzDataTableEntity @ClientTable)) {
                if (-not [string]::IsNullOrEmpty($ClientRow.RowKey)) {
                    $NameByAppId[[string]$ClientRow.RowKey] = [string]$ClientRow.AppName
                }
            }
        } catch {
            # Registry read is best-effort; the chart falls back to AppIds.
            Write-Information "ListApiEgress: ApiClients name lookup failed, using AppIds ($($_.Exception.Message))"
        }

        # Craft stores per-endpoint egress as JSON: label -> [Bytes, Requests, MaxBytes, CacheHits, Errors, Shed].
        $ExpandEndpoints = {
            param($Json, $First = 100)
            $Map = if ($Json) { try { ConvertFrom-Json -InputObject $Json -AsHashtable } catch { $null } }
            if (-not $Map) { return }
            $(foreach ($Label in $Map.Keys) {
                    $Values = @($Map[$Label])
                    [PSCustomObject]@{
                        Endpoint  = [string]$Label
                        Bytes     = [long]$Values[0]
                        Requests  = [long]$Values[1]
                        AvgBytes  = if ([long]$Values[1] -gt 0) { [long][math]::Round($Values[0] / $Values[1]) } else { [long]0 }
                        MaxBytes  = [long]$Values[2]
                        CacheHits = [long]$Values[3]
                        Errors    = [long]$Values[4]
                        Shed      = [long]$Values[5]
                    }
                }) | Sort-Object -Property Bytes -Descending | Select-Object -First $First
        }

        $Clients = @(
            $DailyRows | Where-Object { $_.PartitionKey -notin @($SystemPartition, $InteractivePartition) } | ForEach-Object {
                $AppId = [string]$_.PartitionKey
                [PSCustomObject]@{
                    AppId     = $AppId
                    Name      = if ($NameByAppId[$AppId]) { $NameByAppId[$AppId] } else { $AppId }
                    Bytes     = [long]($_.Bytes ?? 0)
                    Requests  = [long]($_.Requests ?? 0)
                    Shed      = [long]($_.Shed ?? 0)
                    Endpoints = @(& $ExpandEndpoints $_.Endpoints)
                }
            } | Sort-Object -Property Bytes -Descending
        )

        # Signed-in users (UI and delegated MCP) - reported here, never counted toward the cap.
        $InteractiveRow = $DailyRows | Where-Object { $_.PartitionKey -eq $InteractivePartition } | Select-Object -First 1
        $Interactive = if ($InteractiveRow) {
            [PSCustomObject]@{
                Bytes     = [long]($InteractiveRow.Bytes ?? 0)
                Requests  = [long]($InteractiveRow.Requests ?? 0)
                Endpoints = @(& $ExpandEndpoints $InteractiveRow.Endpoints)
            }
        }

        # Per-client 15-minute buckets over the last 24h, shaped for a stacked chart: one row per
        # bucket with a byte column per client (0 when that client had no traffic that bucket).
        $BucketRows = @(Get-CIPPAzDataTableEntity @Table -Filter "RowKey ge '$SinceBucket' and RowKey lt 'bku_'")
        $ClientBuckets = @($BucketRows | Where-Object { $_.PartitionKey -notin @($SystemPartition, $InteractivePartition) })
        # Series = clients seen today or anywhere in the 24h window, biggest-first for a stable stack.
        $ClientIds = @(@($Clients.AppId) + @($ClientBuckets.PartitionKey) | Select-Object -Unique)
        $ClientNames = @{}
        foreach ($AppId in $ClientIds) { $ClientNames[$AppId] = if ($NameByAppId[$AppId]) { $NameByAppId[$AppId] } else { $AppId } }
        $InstanceBuckets = @{}
        foreach ($Bucket in ($BucketRows | Where-Object { $_.PartitionKey -eq $SystemPartition })) { $InstanceBuckets[[string]$Bucket.RowKey] = $Bucket }

        $Trend = @(
            $ClientBuckets | Group-Object -Property RowKey | Sort-Object -Property Name | ForEach-Object {
                $Row = [ordered]@{ BucketStartUtc = $_.Group[0].BucketStartUtc }
                foreach ($AppId in $ClientIds) {
                    $Bucket = $_.Group | Where-Object { $_.PartitionKey -eq $AppId } | Select-Object -First 1
                    $Row[$AppId] = if ($Bucket) { [long]($Bucket.Bytes ?? 0) } else { 0 }
                }
                $Row['TopEndpoints'] = @(& $ExpandEndpoints $InstanceBuckets[$_.Name].Endpoints 5)
                [PSCustomObject]$Row
            }
        )

        $Body = @{
            Results = @{
                Enabled       = $true
                Hosted        = ($env:CIPP_HOSTED -eq 'true')
                DateUtc       = [string]($Instance.DateUtc ?? $Now.ToString('yyyy-MM-dd'))
                CapBytes      = $CapBytes
                Enforcing     = [bool]($Instance.Enforcing ?? ($CapBytes -gt 0))
                BytesToday    = $BytesToday
                PctOfCap      = $PctOfCap
                CapReachedUtc = $Instance.CapReachedUtc
                ShedRequests  = [long]($Instance.Shed ?? 0)
                Clients       = $Clients
                Endpoints     = @(& $ExpandEndpoints $Instance.Endpoints)
                Interactive   = $Interactive
                ClientIds     = $ClientIds
                ClientNames   = $ClientNames
                Trend         = $Trend
            }
        }

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "API egress list error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }
}
