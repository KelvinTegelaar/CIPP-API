function Get-CIPPOneDriveCopyTenantKey {
    <#
    .SYNOPSIS
        Returns the partition keys of a tenant's rows in the OneDriveCopyToUser table.
    .DESCRIPTION
        A copy can be started with a tenant's domain and polled with its tenant id, or with the domain
        in a different case. Rows are therefore written under the tenant's customerId (resolved with
        Get-Tenants), whatever form of the tenant the caller used.

        Key is the partition key new rows are written under. ReadKeys lists the keys to look a copy up
        under, in order: the customerId first, then the tenantFilter exactly as given, because copies
        started before the key was normalised were stored under the raw tenantFilter and must still be
        found. A tenant that Get-Tenants does not know is keyed by its lower-cased tenantFilter.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Raw = $TenantFilter.Trim()
    # Get-Tenants matches customerId and domains exactly (table queries are case-sensitive), and both
    # are stored lower case.
    $Tenant = @(Get-Tenants -TenantFilter $Raw.ToLowerInvariant()) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.customerId) } | Select-Object -First 1
    $Key = if ($Tenant) { ([string]$Tenant.customerId).ToLowerInvariant() } else { $Raw.ToLowerInvariant() }

    $ReadKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($Candidate in @($Key, $Raw)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and -not $ReadKeys.Contains($Candidate)) { $ReadKeys.Add($Candidate) }
    }

    [PSCustomObject]@{
        Key      = $Key
        ReadKeys = @($ReadKeys)
    }
}
