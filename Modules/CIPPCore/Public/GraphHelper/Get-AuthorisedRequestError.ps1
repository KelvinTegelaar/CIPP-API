function Get-AuthorisedRequestError {
    <#
    .SYNOPSIS
        Builds the exception to throw for a tenant that failed Get-AuthorisedRequest.

    .DESCRIPTION
        Works out which actionable case applies, and types the exception so the calling endpoint
        returns the right status through Get-CippErrorStatusCode:
          - the tenant is outside a restricted caller's access -> UnauthorizedAccessException (403)
          - the tenant is present but excluded                  -> UnauthorizedAccessException (403)
          - the tenant is not in the list                       -> ItemNotFoundException (404)

        Deliberately echoes only the identifier the caller already supplied. No tenant names,
        customer ids, or tenant-list contents are disclosed.

        Call this on the deny path only - it performs a tenant lookup.

    .PARAMETER TenantID
        The tenant identifier that was refused.

    .PARAMETER Context
        Short description of the operation, used as the message prefix (e.g. 'Graph request').

    .EXAMPLE
        throw (Get-AuthorisedRequestError -TenantID $tenantid -Context 'Graph request')

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string] $TenantID,
        [string] $Context = 'Request'
    )

    if (-not $TenantID) { $TenantID = $env:TenantID }

    # -IncludeAll: the default lookup leaves excluded tenants out, which hid the excluded case below.
    $Tenant = Get-Tenants -IncludeAll -TenantFilter $TenantID | Select-Object -First 1
    # A tenant-restricted caller only sees their own tenants, so anything outside them means "outside your access"
    # whether or not CIPP manages it - and saying which would reveal what tenants exist.
    if ($script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value -and
        (-not $Tenant -or $script:CippAllowedTenantsStorage.Value -notcontains $Tenant.customerId)) {
        if ($TenantID -eq $env:TenantID) {
            return [System.UnauthorizedAccessException]::new("$Context denied: no tenant was selected, so it ran against the partner tenant, which is outside your access. Select one of your tenants and try again.")
        }
        return [System.UnauthorizedAccessException]::new("$Context denied for '$TenantID': the tenant is outside your access.")
    }
    if ($Tenant -and $Tenant.Excluded -eq $true) {
        return [System.UnauthorizedAccessException]::new("$Context denied for '$TenantID': the tenant is excluded from CIPP management.")
    }
    return [System.Management.Automation.ItemNotFoundException]::new("$Context denied for '$TenantID': the tenant is not in CIPP's tenant list.")
}
