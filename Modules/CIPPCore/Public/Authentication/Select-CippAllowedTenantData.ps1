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

        The stored scope is a list of customerIds (or $null = unrestricted). Cache rows identify
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
        # $null / empty stored scope means the caller is unrestricted - pass everything through
        # with zero overhead (no Get-Tenants call).
        $AllowedCustomerIds = if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value } else { $null }
        $Unrestricted = -not ($AllowedCustomerIds | Where-Object { $_ })

        if (-not $Unrestricted) {
            # Build a case-insensitive set of every identifier a row might carry for an allowed
            # tenant. Get-Tenants is already narrowed to the caller's scope by the storage filter.
            $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Id in $AllowedCustomerIds) {
                if ($Id) { [void]$AllowedSet.Add([string]$Id) }
            }
            foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
                foreach ($Value in @($Tenant.customerId, $Tenant.defaultDomainName, $Tenant.initialDomainName)) {
                    if ($Value) { [void]$AllowedSet.Add([string]$Value) }
                }
            }
            if ($AllowPartner) { [void]$AllowedSet.Add('CIPP') }
        }
    }

    process {
        foreach ($Item in $InputObject) {
            if ($null -eq $Item) { continue }
            if ($Unrestricted) {
                $Item
                continue
            }
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
