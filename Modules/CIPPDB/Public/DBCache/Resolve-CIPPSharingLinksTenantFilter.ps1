function Resolve-CIPPSharingLinksTenantFilter {
    <#
    .SYNOPSIS
        Normalises a tenant GUID to its default domain name.
    .DESCRIPTION
        Add-CIPPDbItem partitions CippReportingDB rows on the default domain, resolving GUID
        tenant filters before writing. Every reader/pruner of those rows must resolve the
        same way or prefix queries silently miss the partition.
    .FUNCTIONALITY
        Internal
    #>
    param([Parameter(Mandatory = $true)][string]$TenantFilter)
    if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
        try {
            $TenantLookup = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)
            if ($TenantLookup.Count -gt 0 -and $TenantLookup[0].defaultDomainName) { return $TenantLookup[0].defaultDomainName }
        } catch {}
    }
    return $TenantFilter
}
