function Set-CIPPDBCacheOfficeActivations {
    <#
    .SYNOPSIS
        Caches Microsoft 365 app activation data per user for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Office activation data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Office activations' -sev Debug

        $Activations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOffice365ActivationsUserDetail?`$format=application%2fjson" -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OfficeActivations' -Data $Activations
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OfficeActivations' -Data $Activations -Count
        $Activations = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Office activations successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Office activations: $($_.Exception.Message)" -sev Error
    }
}
