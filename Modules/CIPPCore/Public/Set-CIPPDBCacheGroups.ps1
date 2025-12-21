function Set-CIPPDBCacheGroups {
    <#
    .SYNOPSIS
        Caches all groups for a tenant

    .PARAMETER TenantFilter
        The tenant to cache groups for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching groups' -sev Info

        $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName,groupTypes,mail,mailEnabled,securityEnabled,membershipRule,onPremisesSyncEnabled' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $Groups
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -Data $Groups -Count
        $Groups = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached groups successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache groups: $($_.Exception.Message)" -sev Error
    }
}
