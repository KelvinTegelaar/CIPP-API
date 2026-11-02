function Set-CIPPDBCacheOrganizationBranding {
    <#
    .SYNOPSIS
        Caches organization branding localizations for a tenant

    .PARAMETER TenantFilter
        The tenant to cache organization branding for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching organization branding localizations' -sev Debug

        $TenantObject = Get-Tenants -TenantFilter $TenantFilter
        $CustomerId = $TenantObject.customerId
        if ([string]::IsNullOrWhiteSpace($CustomerId)) {
            throw "Could not resolve customerId for tenant $TenantFilter"
        }

        $Localizations = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/organization/$CustomerId/branding/localizations" -tenantid $TenantFilter -AsApp $true)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OrganizationBranding' -Data @($Localizations) -AddCount
        $Localizations = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached organization branding localizations successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache organization branding localizations: $($_.Exception.Message)" -sev Error
    }
}
