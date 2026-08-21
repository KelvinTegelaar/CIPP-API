function Set-CIPPDBCachePeopleInsights {
    <#
    .SYNOPSIS
        Caches people insights (Viva insights) organization settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache people insights settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching people insights settings' -sev Debug

        $TenantObject = Get-Tenants -TenantFilter $TenantFilter
        $CustomerId = $TenantObject.customerId
        if ([string]::IsNullOrWhiteSpace($CustomerId)) {
            throw "Could not resolve customerId for tenant $TenantFilter"
        }

        $PeopleInsights = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/organization/$CustomerId/settings/peopleInsights" -tenantid $TenantFilter -AsApp $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PeopleInsights' -Data @($PeopleInsights) -AddCount
        $PeopleInsights = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached people insights settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache people insights settings: $($_.Exception.Message)" -sev Error
    }
}
