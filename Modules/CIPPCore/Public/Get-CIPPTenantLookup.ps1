function Get-CIPPTenantLookup {
    <#
    .SYNOPSIS
        Maps a tenant's customerId, default domain and initial domain to the tenant.
    .DESCRIPTION
        A tenant's default domain can change; its customerId cannot. Store the customerId and
        resolve stored values through this map, which also resolves values saved as a domain.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Tenants)

    $Lookup = @{}
    foreach ($Tenant in @($Tenants ?? (Get-Tenants -IncludeErrors))) {
        foreach ($Key in @($Tenant.customerId, $Tenant.defaultDomainName, $Tenant.initialDomainName)) {
            if ($Key) { $Lookup["$Key"] = $Tenant }
        }
    }
    $Lookup
}
