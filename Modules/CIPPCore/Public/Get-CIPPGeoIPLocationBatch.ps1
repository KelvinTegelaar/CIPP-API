function Get-CIPPGeoIPLocationBatch {
    <#
    .SYNOPSIS
        Resolve many IPs to geo-location in one pass, warming the knownlocationdbv2 cache.
    .DESCRIPTION
        Normalizes + de-dupes the input IPs and drops redacted / reserved / private / link-local
        addresses (never geolocatable). Remaining IPs are seeded from knownlocationdbv2 (fresh
        entries only); cache misses are resolved in bulk via the geoipdb /GetIPInfoBatch endpoint
        (which proxies ip-api's batch API, 100 IPs per upstream request). Successful results are
        written back to knownlocationdbv2 and cachegeoip so later processing is a cache hit.

        Returns a hashtable keyed by normalized IP -> flattened location object
        @{ CountryOrRegion; City; Proxy; Hosting; ASName }. Failed/unknown lookups are NOT cached
        (no poisoning) and are absent from the returned hashtable.

        Used both at ingestion (warm the cache up front) and as a per-batch prefetch in the audit
        log processor (so the per-record loop is a pure in-memory lookup).
    .PARAMETER IPs
        IP addresses to resolve. Duplicates, reserved IPs and ports are handled automatically.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]]$IPs
    )

    # 20s timeout, up to 3 attempts for the geoip HTTP calls. The short timeout stops a single
    # hung IP from stalling the whole batch; the retries ride out transient blips before we give up.
    function Invoke-GeoRetry {
        param([string]$Uri, [string]$Method = 'GET', $Body, [string]$ContentType, [int]$Retries = 3, [int]$TimeoutSec = 20)
        $lastErr = $null
        for ($attempt = 1; $attempt -le $Retries; $attempt++) {
            try {
                if ($PSBoundParameters.ContainsKey('Body')) {
                    return Invoke-CIPPRestMethod -Uri $Uri -Method $Method -Body $Body -ContentType $ContentType -TimeoutSec $TimeoutSec
                } else {
                    return Invoke-CIPPRestMethod -Uri $Uri -Method $Method -TimeoutSec $TimeoutSec
                }
            } catch {
                $lastErr = $_
                if ($attempt -lt $Retries) { Start-Sleep -Milliseconds (300 * $attempt) }
            }
        }
        throw $lastErr
    }

    $ClientIpRegex = [regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
    $ReservedIpRegex = [regex]::new(
        '^(?:10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|(?:22[4-9]|23[0-9]|24[0-9]|25[0-5])\.|::1?$|fe[89ab]|f[cd]|ff)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $Result = @{}

    # Normalize (strip :port / brackets), drop redacted + reserved, de-dupe
    $Distinct = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ip in $IPs) {
        if ([string]::IsNullOrWhiteSpace($ip)) { continue }
        $clean = $ClientIpRegex.Replace(([string]$ip).Trim(), '$1') -replace '[\[\]]', ''
        if ([string]::IsNullOrWhiteSpace($clean) -or $clean -match '[X]+') { continue }
        if ($ReservedIpRegex.IsMatch($clean)) { continue }
        $null = $Distinct.Add($clean)
    }
    if ($Distinct.Count -eq 0) { return $Result }

    $LocationTable = Get-CIPPTable -TableName 'knownlocationdbv2'
    $ValidAfter = (Get-Date).AddDays(-90).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    # In-process memo in front of the table. Despite the name, the seeding loop below issues one
    # table read PER DISTINCT IP - measured at 2.2 ms each, so roughly 450 ms for a 200-IP window,
    # and the audit rule engine calls this once per 500-record slice per tenant. Egress addresses
    # repeat heavily both within a tenant and across them, so the same IPs were re-fetched over and
    # over. Thirty minutes, far inside the table's own 90-day validity, so the memo can only
    # shorten how long a cached answer is reused - never serve something the table would not.
    if ($null -eq $script:GeoIpMemo) { $script:GeoIpMemo = @{} }
    $MemoNow = [datetime]::UtcNow
    $MemoExpiry = $MemoNow.AddMinutes(30)
    # Bounded: sweep expired entries only once the memo is large, so the common path stays O(1).
    if ($script:GeoIpMemo.Count -gt 20000) {
        foreach ($MemoKey in @($script:GeoIpMemo.Keys)) {
            if ($script:GeoIpMemo[$MemoKey].Expires -le $MemoNow) { $script:GeoIpMemo.Remove($MemoKey) }
        }
    }

    # 1) Seed from the memo, then knownlocationdbv2 (fresh, non-Unknown entries); collect the misses
    $ToResolve = [System.Collections.Generic.List[string]]::new()
    foreach ($ip in $Distinct) {
        $Memoised = $script:GeoIpMemo[$ip]
        if ($Memoised -and $Memoised.Expires -gt $MemoNow) {
            $Result[$ip] = $Memoised.Location
            continue
        }
        $cached = Get-CIPPAzDataTableEntity @LocationTable -Filter "PartitionKey eq 'ip' and RowKey eq '$ip' and Timestamp ge datetime'$ValidAfter'"
        if ($cached -and $cached.CountryOrRegion -and $cached.CountryOrRegion -ne 'Unknown') {
            $Result[$ip] = [pscustomobject]@{
                CountryOrRegion = $cached.CountryOrRegion
                City            = $cached.City
                Proxy           = $cached.Proxy
                Hosting         = $cached.Hosting
                ASName          = $cached.ASName
            }
            $script:GeoIpMemo[$ip] = [pscustomobject]@{ Expires = $MemoExpiry; Location = $Result[$ip] }
        } else {
            $ToResolve.Add($ip)
        }
    }
    if ($ToResolve.Count -eq 0) { return $Result }

    # 2) Bulk-resolve the misses via geoipdb /GetIPInfoBatch (chunk to 100 to bound payloads)
    $CacheGeoIPTable = Get-CippTable -TableName 'cachegeoip'
    $KnownEntities = [System.Collections.Generic.List[object]]::new()
    $CacheGeoEntities = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $ToResolve.Count; $i += 100) {
        $chunk = @($ToResolve[$i..([Math]::Min($i + 99, $ToResolve.Count - 1))])
        $payload = '[' + (($chunk | ForEach-Object { $_ | ConvertTo-Json }) -join ',') + ']'
        $resp = $null
        try {
            $resp = Invoke-GeoRetry -Uri 'https://geoipdb.azurewebsites.net/api/GetIPInfoBatch' -Method POST -Body $payload -ContentType 'application/json'
        } catch {
            #Write-LogMessage -API GeoIPLocation -message "Bulk geoip lookup failed, falling back to single lookups for $($chunk.Count) IP(s): $($_.Exception.Message)" -sev Warning
            $fb = [System.Collections.Generic.List[object]]::new()
            foreach ($ip in $chunk) {
                try {
                    $s = Invoke-GeoRetry -Uri "https://geoipdb.azurewebsites.net/api/GetIPInfo?IP=$ip"
                    if ($s -and $s.status -ne 'fail') { $fb.Add([pscustomobject]@{ query = $ip; status = 'success'; countryCode = $s.countryCode; city = $s.city; proxy = $s.proxy; hosting = $s.hosting; asname = $s.asname }) }
                } catch { }
            }
            $resp = $fb
        }
        foreach ($r in $resp) {
            $ip = [string]$r.query
            if ([string]::IsNullOrWhiteSpace($ip) -or $r.status -ne 'success') { continue }
            $loc = [pscustomobject]@{
                CountryOrRegion = if ($r.countryCode) { $r.countryCode } else { 'Unknown' }
                City            = if ($r.city) { $r.city } else { 'Unknown' }
                Proxy           = if ($null -ne $r.proxy) { $r.proxy } else { 'Unknown' }
                Hosting         = if ($null -ne $r.hosting) { $r.hosting } else { 'Unknown' }
                ASName          = if ($r.asname) { $r.asname } else { 'Unknown' }
            }
            $Result[$ip] = $loc
            # Only cache real results - never persist Unknown (no poisoning, matches single path).
            # The memo follows the same rule, or an unresolvable address would be pinned as Unknown
            # for the whole TTL instead of being retried.
            if ($loc.CountryOrRegion -ne 'Unknown') {
                $script:GeoIpMemo[$ip] = [pscustomobject]@{ Expires = $MemoExpiry; Location = $loc }
                $KnownEntities.Add(@{
                        PartitionKey    = 'ip'
                        RowKey          = $ip
                        CountryOrRegion = "$($loc.CountryOrRegion)"
                        City            = "$($loc.City)"
                        Proxy           = "$($loc.Proxy)"
                        Hosting         = "$($loc.Hosting)"
                        ASName          = "$($loc.ASName)"
                    })
                $CacheGeoEntities.Add(@{
                        PartitionKey = 'IP'
                        RowKey       = $ip
                        Data         = [string]($r | ConvertTo-Json -Compress)
                    })
            }
        }
    }

    # 3) Batch-write the caches
    if ($KnownEntities.Count -gt 0) {
        try { $null = Add-CIPPAzDataTableEntity @LocationTable -Entity @($KnownEntities) -Force }
        catch { Write-LogMessage -API GeoIPLocation -message "Failed to cache $($KnownEntities.Count) bulk geo results: $($_.Exception.Message)" -sev Warning }
    }
    if ($CacheGeoEntities.Count -gt 0) {
        try { $null = Add-AzDataTableEntity @CacheGeoIPTable -Entity @($CacheGeoEntities) -Force } catch {}
    }

    return $Result
}
