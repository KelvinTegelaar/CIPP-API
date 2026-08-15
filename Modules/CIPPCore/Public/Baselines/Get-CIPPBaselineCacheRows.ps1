function Get-CIPPBaselineCacheRows {
    <#
    .SYNOPSIS
        Reads a CIPPDb cache type for a prepare hook, collecting it once if it is empty.
    .DESCRIPTION
        The engine collects on a miss for exactly ONE cache type - the definition's
        read.cacheType. A prepare hook that joins a SECOND type has no such safety net: if
        that type has never been collected for a tenant, the hook returns a null Current, the
        engine collects the primary type (which was never the problem), re-runs the hook, gets
        null again and parks the row at No Data. Forever, on that tenant, with a message
        naming the wrong cache.

        Every hook that reads a cache the definition does not declare must therefore go
        through this. It reads, and on an empty read triggers Set-CIPPDBCache<Type> once and
        re-reads. A type with no collector, or a collector that fails, yields an empty set -
        the caller decides whether that means No Data.

        Pass CollectorArgs for umbrella collectors whose default is their heaviest option, the
        same way a definition declares read.collectorArgs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [hashtable]$CollectorArgs = @{}
    )

    $Rows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type | Where-Object { $_ })
    if ($Rows.Count -gt 0) { return $Rows }

    $Collector = Get-Command -Name "Set-CIPPDBCache$Type" -ErrorAction SilentlyContinue
    if (-not $Collector) {
        Write-Information "Baselines: no collector exists for cache type $Type on $TenantFilter."
        return @()
    }

    try {
        $CollectParams = @{ TenantFilter = $TenantFilter }
        foreach ($Key in $CollectorArgs.Keys) { $CollectParams[$Key] = $CollectorArgs[$Key] }
        $null = & $Collector @CollectParams
    } catch {
        Write-Information "Baselines: collecting $Type on $TenantFilter failed: $($_.Exception.Message)"
        return @()
    }

    @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type | Where-Object { $_ })
}
