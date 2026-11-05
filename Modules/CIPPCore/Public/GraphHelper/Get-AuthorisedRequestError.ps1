function Get-AuthorisedRequestError {
    <#
    .SYNOPSIS
        Builds an actionable message for a tenant that failed Get-AuthorisedRequest.

    .DESCRIPTION
        Get-AuthorisedRequest only returns a boolean, so every caller historically emitted the
        same catch-all: "You cannot manage your own tenant or tenants not under your scope".
        That conflated two situations with different fixes, and was misleading besides - the
        partner tenant is present in Get-Tenants, so "your own tenant" was rarely the reason.

        This works out which of the two actionable cases applies:
          - the tenant is present but excluded  -> un-exclude it in CIPP
          - the tenant is not in the list       -> tenant sync / GDAP scope

        Deliberately echoes only the identifier the caller already supplied. No tenant names,
        customer ids, or tenant-list contents are disclosed.

        Call this on the deny path only - it performs a tenant lookup.

    .PARAMETER TenantID
        The tenant identifier that was refused.

    .PARAMETER Context
        Short description of the operation, used as the message prefix (e.g. 'Graph request').

    .EXAMPLE
        Write-Error (Get-AuthorisedRequestError -TenantID $tenantid -Context 'Graph request')

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string] $TenantID,
        [string] $Context = 'Request'
    )

    if (-not $TenantID) { $TenantID = $env:TenantID }

    $Tenant = Get-Tenants -IncludeErrors -TenantFilter $TenantID | Select-Object -First 1
    # A tenant-restricted caller only sees their own tenants, so a miss means "outside your access"
    # whether or not CIPP manages it - and saying which would reveal what tenants exist.
    if (-not $Tenant -and $script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value) {
        if ($TenantID -eq $env:TenantID) {
            return "$Context denied: no tenant was selected, so it ran against the partner tenant, which is outside your access. Select one of your tenants and try again."
        }
        return "$Context denied for '$TenantID': the tenant is outside your access."
    }
    $Reason = if ($Tenant -and $Tenant.Excluded -eq $true) {
        'the tenant is excluded from CIPP management'
    } else {
        "the tenant is not in CIPP's tenant list"
    }

    return "$Context denied for '$TenantID': $Reason."
}
