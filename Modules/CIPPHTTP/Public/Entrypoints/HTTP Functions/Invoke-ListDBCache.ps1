function Invoke-ListDBCache {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Retrieves cached tenant data from the CIPP reporting database (CippReportingDB). This is the fastest
        and most efficient way to query tenant data across single or multiple tenants. The database is populated
        nightly by background cache jobs, so data is typically at most 24 hours old.

        Required query parameters:
          - tenantFilter: The tenant domain or 'AllTenants' to query all managed tenants.
          - type: The cache collection to retrieve (e.g. Users, Groups, Mailboxes, Devices, etc.).

        Use type=_availableTypes to discover which cache collections exist for a given tenant. Omitting the
        type parameter also returns the available types.

        PERFORMANCE GUIDANCE: For AllTenants queries or any bulk/cross-tenant data retrieval, prefer
        ListDBCache over calling individual endpoints (e.g. ListUsers, ListGroups, ListMailboxes) directly.
        Individual endpoints make live API calls per tenant which is significantly slower and may hit
        throttling limits. ListDBCache reads pre-cached data from Azure Table Storage and returns results
        in seconds regardless of tenant count.

        Recommended workflow for MCP tool selection:
          1. Call ListDBCache with type=_availableTypes to discover available cache collections.
          2. If the data you need exists as a cache type, use ListDBCache with that type.
          3. Only fall back to individual List* endpoints when you need real-time data for a single tenant
             or when the data is not available in the cache.

        Common cache types include: Users, Groups, Mailboxes, Devices, ConditionalAccess, Applications,
        IntunePolicy, CompliancePolicy, and many more. The exact set depends on what has been configured.
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $TenantFilter = $Request.Query.tenantFilter
    $Type = $Request.Query.type

    $Tenant = if ($TenantFilter -ne 'AllTenants') { (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName } else { $TenantFilter }

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: tenantFilter query parameter is required' }
            })
    }

    if (-not $Type) {
        $Types = Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant | Select-Object -ExpandProperty RowKey
        $Types = $Types | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    Results        = 'Error: type query parameter is required'
                    AvailableTypes = $Types
                }
            })
    }

    if ($Type -eq '_availableTypes') {
        $Types = Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant | Select-Object -ExpandProperty RowKey
        $Types = $Types | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = @($Types) }
            })
    }

    if ($Tenant) {
        $Results = New-CIPPDbRequest -TenantFilter $Tenant -Type $Type
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
}
