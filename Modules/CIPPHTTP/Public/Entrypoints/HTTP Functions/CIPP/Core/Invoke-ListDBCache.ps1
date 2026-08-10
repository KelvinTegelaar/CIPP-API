function Invoke-ListDBCache {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Retrieves cached tenant data from the CIPP reporting database (CippReportingDB). This is the fastest
        and most efficient way to query tenant data across single or multiple tenants. The database is populated
        nightly by background cache jobs, so data is typically at most 24 hours old.

        Required query parameters:
          - tenantFilter: The tenant domain or 'AllTenants' to query all managed tenants.
          - type: The cache collection to retrieve (e.g. Users, Groups, Mailboxes, Devices, etc.).
                  Not required when countsOnly=true.

        Optional query parameters:
          - countsOnly: When 'true', returns one row per tenant per collection containing only the record
                        count and the time that collection was last cached. This reads the pre-computed
                        '<Type>-Count' rows, so it is a single table query regardless of tenant count and
                        never materializes the underlying records. Combine with tenantFilter=AllTenants to
                        get an estate-wide inventory and per-tenant cache freshness in one call. Pass a
                        type alongside it to restrict the result to a single collection.

        Use type=_availableTypes to discover which cache collections exist for a given tenant. Omitting the
        type parameter also returns the available types.

        PERFORMANCE GUIDANCE: For AllTenants queries or any bulk/cross-tenant data retrieval, prefer
        ListDBCache over calling individual endpoints (e.g. ListUsers, ListGroups, ListMailboxes) directly.
        Individual endpoints make live API calls per tenant which is significantly slower and may hit
        throttling limits. ListDBCache reads pre-cached data from Azure Table Storage and returns results
        in seconds regardless of tenant count.

        Note that tenantFilter=AllTenants WITH a type performs a cross-partition scan and materializes every
        record of that collection across every tenant, so it grows with the size of the estate. Where only
        totals are needed, countsOnly=true is dramatically cheaper and should always be preferred.

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

    $APIName = $TriggerMetadata.FunctionName
    $TenantFilter = $Request.Query.tenantFilter
    $Type = $Request.Query.type
    $CountsOnly = $Request.Query.countsOnly -eq $true

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: tenantFilter query parameter is required' }
            })
    }

    try {
        $IsAllTenants = $TenantFilter -eq 'AllTenants'

        if ($IsAllTenants) {
            # Get-CIPPDbItem drops the PartitionKey clause for this sentinel, querying every tenant.
            $Tenant = 'allTenants'
        } else {
            $Tenant = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
            if (-not $Tenant) {
                throw "Tenant '$TenantFilter' not found"
            }
        }

        # This endpoint is marked AnyTenant so that tenantFilter=AllTenants is reachable, which means the
        # framework's per-tenant check in Test-CIPPAccess is skipped for custom-role users. Scoping is
        # therefore enforced here, for BOTH paths. Test-CIPPAccess returns permitted customerIds (or
        # 'AllTenants' when unrestricted); CippReportingDB partitions by defaultDomainName, so the ids have
        # to be translated before they can be matched against rows.
        $AllowedDomains = $null
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $AllowedDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($AllowedTenant in (Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants })) {
                if ($AllowedTenant.defaultDomainName) {
                    [void]$AllowedDomains.Add([string]$AllowedTenant.defaultDomainName)
                }
            }

            # A single-tenant request would otherwise be unguarded now that AnyTenant is set.
            if (-not $IsAllTenants -and -not $AllowedDomains.Contains([string]$Tenant)) {
                throw 'Access to this tenant is not allowed'
            }
        }

        if ($CountsOnly) {
            $CountParams = @{ CountsOnly = $true; TenantFilter = $Tenant }
            if ($Type -and $Type -ne '_availableTypes') { $CountParams.Type = $Type }
            $Rows = @(Get-CIPPDbItem @CountParams)

            if ($null -ne $AllowedDomains) {
                $Rows = @($Rows | Where-Object { $AllowedDomains.Contains([string]$_.PartitionKey) })
            }

            $Results = @($Rows | ForEach-Object {
                    [PSCustomObject]@{
                        Tenant      = $_.PartitionKey
                        Type        = $_.RowKey -replace '-Count$', ''
                        Count       = $_.DataCount
                        LastRefresh = $_.Timestamp
                    }
                })

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = $Results }
                })
        }

        if (-not $Type -or $Type -eq '_availableTypes') {
            $TypeRows = @(Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant)
            if ($null -ne $AllowedDomains) {
                $TypeRows = @($TypeRows | Where-Object { $AllowedDomains.Contains([string]$_.PartitionKey) })
            }
            $Types = @($TypeRows.RowKey | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object -Unique)

            if (-not $Type) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{
                            Results        = 'Error: type query parameter is required'
                            AvailableTypes = $Types
                        }
                    })
            }

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = $Types }
                })
        }

        if ($IsAllTenants) {
            # New-CIPPDbRequest resolves the tenant through Get-Tenants, which has no 'AllTenants' entry, so
            # it cannot serve this path. Read the rows directly and parse them the same way it would.
            $Rows = @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type)
            if ($null -ne $AllowedDomains) {
                $Rows = @($Rows | Where-Object { $AllowedDomains.Contains([string]$_.PartitionKey) })
            }

            $Results = foreach ($Row in $Rows) {
                if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
                try {
                    $Parsed = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
                } catch {
                    Write-Information "Skipping unparseable CippReportingDB row for '$($Row.PartitionKey)'/'$Type': $($_.Exception.Message)"
                    continue
                }
                # A row whose Data is a JSON array unrolls into multiple records; stamp the owning tenant on
                # each so cross-tenant results stay attributable (CippDataTable renders a Tenant column from it).
                foreach ($Record in @($Parsed)) {
                    if ($Record -is [System.Management.Automation.PSObject] -or $Record -is [PSCustomObject]) {
                        $Record | Add-Member -MemberType NoteProperty -Name 'Tenant' -Value $Row.PartitionKey -Force
                    }
                    $Record
                }
            }
            $Results = @($Results)
        } else {
            $Results = @(New-CIPPDbRequest -TenantFilter $Tenant -Type $Type)
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list DB cache: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $ErrorMessage.NormalizedError }
            })
    }
}
