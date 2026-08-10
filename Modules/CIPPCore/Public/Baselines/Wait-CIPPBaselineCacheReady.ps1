function Wait-CIPPBaselineCacheReady {
    <#
    .SYNOPSIS
        Single-flight cache pre-check for template-backed baseline standards.
    .DESCRIPTION
        Template standards' verdicts drive policy deploys, and their domains (CA and
        Intune policies) change under external hands - so before any read the cache
        must be COMPLETE, RECENT and, where a cheap live probe exists, MATCH the
        tenant's live state. Refresh triggers:
          - the representative freshness cache is missing or older than 3 hours
          - any of the definition's read.requiredCaches has no Count metadata at all
          - read.liveCount is configured and a live id-only Graph read disagrees with
            the cached count (catches external adds/deletes between cache cadences)
        Exactly ONE job per (tenant, cacheType) performs the collection - a lock row in
        CippBaselineCacheLocks is claimed atomically (Add without -Force throws on an
        existing entity); every other job WAITS for the lock to clear instead of racing
        the collector and comparing against a half-written cache. Stale locks (a worker
        died mid-collection) are stolen after 10 minutes.
    .OUTPUTS
        $true when the cache was refreshed during this call (by this job or by a peer
        this job waited on) - callers treat it like their own refresh and skip
        collector-on-miss retries. $false when the cache was already ready.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $Definition,
        $RunId
    )

    $CacheCollector = Get-Command -Name "Set-CIPPDBCache$($Definition.read.cacheType)" -ErrorAction SilentlyContinue
    if (-not $CacheCollector) { return $false }

    # --- pre-check: is the cache complete, recent and consistent with live state?
    $NeedsRefresh = $false
    $Reason = $null
    $FreshnessType = $Definition.read.freshnessType ?? $Definition.read.cacheType
    $CacheMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $FreshnessType -CountsOnly } catch { $null })
    if ($null -eq $CacheMeta -or $CacheMeta.Timestamp -lt (Get-Date).AddHours(-3)) {
        $NeedsRefresh = $true
        $Reason = "representative cache $FreshnessType is missing or stale"
    }

    if (-not $NeedsRefresh) {
        # Completeness: umbrella collectors store rows under many family cache types -
        # every family the prepare can read must have been collected at least once
        # (Count metadata exists even for a genuinely empty family).
        foreach ($RequiredCache in @($Definition.read.requiredCaches)) {
            if (-not $RequiredCache) { continue }
            $RequiredMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $RequiredCache -CountsOnly } catch { $null })
            if ($null -eq $RequiredMeta) {
                $NeedsRefresh = $true
                $Reason = "required cache $RequiredCache has never been collected"
                break
            }
        }
    }

    if (-not $NeedsRefresh -and $Definition.read.liveCount.uri) {
        # Live-count probe: an id-only read of the live collection, compared against the
        # cached count. Deliberate per-run cost - these are the areas most likely to be
        # changed externally, and a mismatch means alerts would fire on stale state.
        try {
            $LiveRows = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($Definition.read.liveCount.uri)?`$select=id&`$top=999" -tenantid $TenantFilter
            $LiveCount = @($LiveRows | Where-Object { $_.id }).Count
            $CountedType = $Definition.read.liveCount.cacheType ?? $FreshnessType
            $CountedMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $CountedType -CountsOnly } catch { $null })
            if ($LiveCount -ne [int]($CountedMeta.DataCount ?? 0)) {
                $NeedsRefresh = $true
                $Reason = "live count ($LiveCount) differs from cached count ($([int]($CountedMeta.DataCount ?? 0))) for $CountedType"
            }
        } catch {
            Write-Information "Wait-CIPPBaselineCacheReady: live count probe for $($Definition.read.liveCount.uri) on $TenantFilter failed: $($_.Exception.Message)"
        }
    }

    if (-not $NeedsRefresh) { return $false }

    # --- single-flight: claim the (tenant, cacheType) lock or wait for its holder.
    $LockTable = Get-CippTable -tablename 'CippBaselineCacheLocks'
    $LockPartition = "$TenantFilter"
    $LockKey = "$($Definition.read.cacheType)"
    $Now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $LockPartition
    $SafeLockKey = ConvertTo-CIPPODataFilterValue -Value $LockKey

    $Claimed = $false
    try {
        # Add WITHOUT -Force is an atomic insert: it throws when the entity exists.
        Add-CIPPAzDataTableEntity @LockTable -Entity @{ PartitionKey = $LockPartition; RowKey = $LockKey; LockedAt = $Now; RunId = "$RunId" }
        $Claimed = $true
    } catch {
        $ExistingLock = Get-CIPPAzDataTableEntity @LockTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeLockKey'" | Select-Object -First 1
        if ($ExistingLock -and [int64]($ExistingLock.LockedAt ?? 0) -lt ($Now - 600)) {
            # The holder died mid-collection: steal the lock and collect ourselves.
            try {
                Add-CIPPAzDataTableEntity @LockTable -Entity @{ PartitionKey = $LockPartition; RowKey = $LockKey; LockedAt = $Now; RunId = "$RunId" } -Force
                $Claimed = $true
            } catch { }
        }
    }

    if ($Claimed) {
        Write-Information "Wait-CIPPBaselineCacheReady: refreshing $LockKey for ${TenantFilter}: $Reason"
        try {
            $null = & $CacheCollector -TenantFilter $TenantFilter
        } catch {
            Write-Information "Wait-CIPPBaselineCacheReady: cache refresh for $LockKey on $TenantFilter failed: $($_.Exception.Message)"
        } finally {
            try { Remove-CIPPAzDataTableEntity -Force @LockTable -Entity @{ PartitionKey = $LockPartition; RowKey = $LockKey } } catch { }
        }
        return $true
    }

    # A peer holds the lock and is collecting right now: wait for it instead of racing.
    $Deadline = $Now + 240
    while ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $Deadline) {
        Start-Sleep -Seconds 5
        $ExistingLock = Get-CIPPAzDataTableEntity @LockTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeLockKey'" | Select-Object -First 1
        if (-not $ExistingLock) { return $true }
    }
    Write-Information "Wait-CIPPBaselineCacheReady: gave up waiting for the $LockKey lock on $TenantFilter after 240s - proceeding with the freshest available cache."
    return $true
}
