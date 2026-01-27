function Set-CIPPDBCacheGuests {
    <#
    .SYNOPSIS
        Caches all guest users for a tenant

    .PARAMETER TenantFilter
        The tenant to cache guest users for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching guest users' -sev Debug

        $Guests = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=userType eq 'Guest'&`$expand=sponsors&`$top=999" -tenantid $TenantFilter
        if (!$Guests) { $Guests = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Guests' -Data $Guests
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Guests' -Data $Guests -Count
        $Guests = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached guest users successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache guest users: $($_.Exception.Message)" -sev Error
    }
}
