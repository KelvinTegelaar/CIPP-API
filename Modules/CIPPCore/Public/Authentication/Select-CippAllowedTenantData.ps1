function Select-CippAllowedTenantData {
    <#
    .SYNOPSIS
        Narrow a set of cached rows to the tenants the current caller is allowed to see.

    .DESCRIPTION
        A family of cached List*/Exec*List endpoints reads a global cache table by PartitionKey
        and returns the rows directly. When a tenant-restricted custom role calls one of these
        with tenantFilter=AllTenants, the read must still be narrowed to the caller's allowed
        tenants - the same scope Get-Tenants already applies via $script:CippAllowedTenantsStorage.
        A direct cache-table read never touches Get-Tenants on a cache hit, so it would otherwise
        leak every managed tenant's data. Pipe those rows through this function at the point they
        become the response to close that gap.

        This function MUST live in CIPPCore. The $script:CippAllowedTenantsStorage AsyncLocal slot
        is CIPPCore module-scoped; a copy defined in CIPPHTTP would read that module's own empty
        variable and silently filter nothing (see Get-CippRequestContext).

        The stored scope is a list of customerIds. $null means unrestricted; any non-null scope -
        including an empty list, which a role produces when every allowed tenant is also blocked
        or an allowed tenant group expands to no members - means restricted and must fail closed
        rather than fall through to the unrestricted path. Cache rows identify
        their tenant by domain name (defaultDomainName, stored on a 'Tenant' property) and/or by
        customerId, so allowed customerIds are expanded to every identifier form an allowed tenant
        might present, mirroring the match logic in Invoke-ListLogs.

    .PARAMETER InputObject
        The rows to filter. Accepts pipeline input.

    .PARAMETER TenantProperty
        The property name(s) on each row that identify its tenant. Defaults to 'Tenant' and
        'TenantId'. A row is kept when any of these properties matches an allowed tenant. For the
        Lighthouse aggregate use 'organizationId'.

    .PARAMETER AllowPartner
        Also keep rows whose Tenant equals 'CIPP' (system/partner rows), mirroring Invoke-ListLogs.

    .EXAMPLE
        $Rows = $Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant'

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject,

        [string[]]$TenantProperty = @('Tenant', 'TenantId'),

        [switch]$AllowPartner
    )

    begin {
        # A $null stored scope means the caller is unrestricted - pass everything through with
        # zero overhead (no Get-Tenants call). An explicit scope that resolves to zero usable ids
        # is a restricted caller entitled to nothing, and has to deny rather than degrade into the
        # unrestricted path. The two cannot be told apart with plain truthiness ($null and @() are
        # both falsy), and the null test must run against the property itself: routing .Value
        # through an intermediate statement-expression unwraps an empty array to $null, which is
        # exactly the collapse that used to leak every tenant's rows.
        $Unrestricted = -not $script:CippAllowedTenantsStorage -or $null -eq $script:CippAllowedTenantsStorage.Value
        $DenyAll = $false

        if (-not $Unrestricted) {
            $AllowedCustomerIds = @($script:CippAllowedTenantsStorage.Value | Where-Object { $_ })
            if ($AllowedCustomerIds.Count -eq 0) {
                $DenyAll = $true
            } else {
                # Build a case-insensitive set of every identifier a row might carry for an allowed
                # tenant. Get-Tenants is already narrowed to the caller's scope by the storage filter.
                $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Id in $AllowedCustomerIds) {
                    [void]$AllowedSet.Add([string]$Id)
                }
                foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
                    foreach ($Value in @($Tenant.customerId, $Tenant.defaultDomainName, $Tenant.initialDomainName)) {
                        if ($Value) { [void]$AllowedSet.Add([string]$Value) }
                    }
                }
                if ($AllowPartner) { [void]$AllowedSet.Add('CIPP') }
            }
        }
    }

    process {
        foreach ($Item in $InputObject) {
            if ($null -eq $Item) { continue }
            if ($Unrestricted) {
                $Item
                continue
            }
            if ($DenyAll) { continue }
            foreach ($Prop in $TenantProperty) {
                $Value = $Item.$Prop
                if ($Value -and $AllowedSet.Contains([string]$Value)) {
                    $Item
                    break
                }
            }
        }
    }
}
