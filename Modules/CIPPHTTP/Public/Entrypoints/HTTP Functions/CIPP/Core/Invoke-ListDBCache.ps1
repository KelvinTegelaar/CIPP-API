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

        Optional query parameters:
          - type: The cache collection to retrieve (e.g. Users, Groups, Mailboxes, Devices, etc.).
                  Omit it (or pass type=_availableTypes) to get the list of collections for the tenant
                  instead of records; it is also not needed when countsOnly=true.
          - countsOnly: When 'true', returns one row per tenant per collection containing only the record
                        count and the time that collection was last cached. This reads the pre-computed
                        '<Type>-Count' rows, so it is a single table query regardless of tenant count and
                        never materializes the underlying records. Combine with tenantFilter=AllTenants to
                        get an estate-wide inventory and per-tenant cache freshness in one call. Pass a
                        type alongside it to restrict the result to a single collection.
          - select: Comma-separated list of top-level fields to keep on each record (e.g.
                    select=id,displayName,userPrincipalName). Everything else is dropped during parse,
                    shrinking the response. A kept field keeps its ENTIRE subtree, so select=conditions
                    keeps conditions.users.includeRoles too; projection never reaches inside a kept
                    value. The owning Tenant is always stamped on each record regardless of select.
          - top: Return at most this many records. For tenantFilter=AllTenants this is a GLOBAL cap
                 across all tenants when ungrouped, so use it to sample rather than to page. When
                 groupBy=Tenant is also set, top instead caps the records within each tenant bucket.
          - latestOnly: When 'true', keep only the newest record per tenant, ranked by dateField (or
                        an auto-detected date field such as createdDateTime). Collapses per-day
                        snapshot types like SecureScore to one current row per tenant.
          - groupBy: Set to 'Tenant' to return one bucket per tenant as
                     { Tenant, Count, Records } objects instead of a flat record list.
          - dateField: The record field latestOnly ranks by. Omit to auto-detect.

        Use type=_shape for every collection's row count and fields (recorded when the cache was written).
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
    # Comma-separated list of top-level fields to keep on each record; everything else is dropped
    # during parse. A kept field keeps its ENTIRE subtree (e.g. select=conditions keeps
    # conditions.users.includeRoles). The Tenant stamp is always preserved. Omit to return all fields.
    $Select = $Request.Query.select
    # Return at most this many records. For AllTenants this is a global cap across all tenants,
    # unless groupBy=Tenant is set, in which case it caps records within each tenant bucket.
    $Top = $Request.Query.top -as [int]
    # When true, keep only the newest record per tenant (by dateField, or an auto-detected date field).
    # Collapses e.g. SecureScore's per-day snapshots to one current row per tenant.
    $LatestOnly = $Request.Query.latestOnly -eq $true
    # Group the result into one bucket per tenant. Only 'Tenant' is supported.
    $GroupBy = $Request.Query.groupBy
    # The record date field latestOnly ranks by. Omit to auto-detect (createdDateTime, lastRefresh, etc).
    $DateField = $Request.Query.dateField

    $SelectFields = if ($Select) {
        [string[]]@($Select -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        $null
    }

    # Ranks a parsed record by a date field for latestOnly. Uses the caller's dateField when given,
    # otherwise the first present candidate; unparseable/absent dates sort oldest.
    $DateCandidates = @('createdDateTime', 'createdDate', 'CreatedDateTime', 'lastRefresh', 'LastRefresh', 'activityDateTime', 'date', 'Date', 'Timestamp')
    $GetRecordDate = {
        param($Record)
        $Value = $null
        if ($DateField) {
            $Value = $Record.$DateField
        } else {
            foreach ($Candidate in $DateCandidates) {
                $Prop = $Record.PSObject.Properties[$Candidate]
                if ($Prop -and $Prop.Value) { $Value = $Prop.Value; break }
            }
        }
        if ($null -eq $Value) { return [datetime]::MinValue }
        try { return [datetime]$Value } catch { return [datetime]::MinValue }
    }

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

        # type=_shape: every collection with its row count and the fields (and types) its rows were seen
        # to carry, as recorded when the cache was written. What the report builder offers to pick from.
        if ($Type -eq '_shape') {
            $ShapeRows = @(Get-CIPPDbItem -CountsOnly -IncludeShape -TenantFilter $Tenant)
            if ($null -ne $AllowedDomains) {
                $ShapeRows = @($ShapeRows | Where-Object { $AllowedDomains.Contains([string]$_.PartitionKey) })
            }
            $Shapes = @($ShapeRows | Sort-Object -Property RowKey | ForEach-Object {
                    $Fields = try { @((ConvertFrom-Json -InputObject "$($_.Shape)" -ErrorAction Stop).fields) } catch { @() }
                    [PSCustomObject]@{
                        Type   = $_.RowKey -replace '-Count$', ''
                        Count  = $_.DataCount
                        Fields = @($Fields | Where-Object { $_.name } | ForEach-Object { [PSCustomObject]@{ name = [string]$_.name; type = [string]$_.type } })
                    }
                })
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = $Shapes }
                })
        }

        # type is optional: omitting it (or passing _availableTypes) returns the list of cache
        # collections for the tenant, so a type-less call is a discovery call rather than an error.
        # This also keeps the OpenAPI generator from marking type required off a missing-type guard;
        # type is only meaningful for a data read, which countsOnly and this discovery path bypass.
        if (-not $Type -or $Type -eq '_availableTypes') {
            $TypeRows = @(Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant)
            if ($null -ne $AllowedDomains) {
                $TypeRows = @($TypeRows | Where-Object { $AllowedDomains.Contains([string]$_.PartitionKey) })
            }
            $Types = @($TypeRows.RowKey | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object -Unique)

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
                    $Parsed = [CIPP.CippJson]::ConvertFromJson($Row.Data, $SelectFields)
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
            $DbParams = @{ TenantFilter = $Tenant; Type = $Type }
            if ($SelectFields) { $DbParams.Fields = $SelectFields }
            $Results = @(New-CIPPDbRequest @DbParams)
        }

        if ($LatestOnly) {
            # Keep only the newest record per tenant. Single-tenant results collapse to one row.
            $Results = @($Results | Group-Object -Property Tenant | ForEach-Object {
                    @($_.Group) | Sort-Object -Property @{ Expression = { & $GetRecordDate $_ } } -Descending | Select-Object -First 1
                })
        }

        if ($GroupBy -eq 'Tenant') {
            # One bucket per tenant; top (when set) caps the records inside each bucket.
            $Results = @($Results | Group-Object -Property Tenant | ForEach-Object {
                    $BucketRecords = @($_.Group)
                    if ($Top -gt 0) { $BucketRecords = @($BucketRecords | Select-Object -First $Top) }
                    [PSCustomObject]@{
                        Tenant  = $_.Name
                        Count   = @($_.Group).Count
                        Records = $BucketRecords
                    }
                })
        } elseif ($Top -gt 0) {
            $Results = @($Results | Select-Object -First $Top)
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
