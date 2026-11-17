function Get-CIPPOneDriveCopyTenantKey {
    <#
    .SYNOPSIS
        Returns the OneDriveCopyToUser partition key for a tenant: its customerId, so a copy started with the domain can be polled with the tenant id.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Lower = $TenantFilter.Trim().ToLowerInvariant()
    # Get-Tenants matches exactly, and stores customerId and domains lower case.
    $Tenant = @(Get-Tenants -TenantFilter $Lower).Where({ -not [string]::IsNullOrWhiteSpace([string]$_.customerId) }, 'First')[0]
    if ($Tenant) { ([string]$Tenant.customerId).ToLowerInvariant() } else { $Lower }
}
