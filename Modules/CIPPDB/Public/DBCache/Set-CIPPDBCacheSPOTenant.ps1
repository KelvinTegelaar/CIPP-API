function Set-CIPPDBCacheSPOTenant {
    <#
    .SYNOPSIS
        Caches SharePoint Online tenant configuration

    .DESCRIPTION
        Wraps Get-CIPPSPOTenant (which uses the SPO admin SOAP endpoint via
        New-GraphPostRequest) and writes the result into the CippReportingDB
        under Type 'SPOTenant'. The single configuration object is wrapped in
        an array for consistency with the other ExoOrganizationConfig-style
        single-row caches.

    .PARAMETER TenantFilter
        The tenant to cache SPO tenant configuration for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId,
        # SharePoint app-only requires the SAM certificate. Opt-in per caller (e.g. a baseline's
        # read.collectorArgs) so this shared collector's default (delegated) is unchanged.
        [switch]$UseCertificate
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint Online tenant configuration' -sev Debug

        $AuthSplat = @{}
        if ($UseCertificate) { $AuthSplat['UseCertificate'] = $true }
        $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter -SkipCache @AuthSplat

        # An empty response is a failure too: this collection only runs for SharePoint-licensed
        # tenants, so there is always a configuration object to return. Falling through quietly
        # left the stored count row untouched and indistinguishable from a successful run.
        if (-not $SPOTenant) {
            throw 'The SharePoint admin endpoint returned no tenant configuration'
        }

        $SPOTenantArray = @($SPOTenant)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenant' -Data $SPOTenantArray -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint Online tenant configuration' -sev Debug
        $SPOTenant = $null

    } catch {
        # A tenant with no SharePoint consent is not a failed collection - it is a tenant nobody has
        # consented yet, and it will answer 401 every night until that changes. Failing the activity
        # for it would bury genuine failures under a permanent one, so record it and move on. The
        # data still reads as stale on the dashboard, because it is.
        if ($_.Exception.Data['SPOAccessDenied']) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $_.Exception.Message -sev Warning
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SPO tenant configuration: $($_.Exception.Message)" -sev Error
        # Anything else is unexpected, so let the caller count it. Swallowing left
        # Invoke-CIPPDBCacheCollection reporting 'N succeeded, 0 failed' and the queue Completed
        # while the count row silently kept its old timestamp.
        throw
    }
}
