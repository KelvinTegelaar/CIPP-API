function Set-CIPPDBCacheMFAState {
    <#
    .SYNOPSIS
        Caches MFA state for a tenant

    .PARAMETER TenantFilter
        The tenant to cache MFA state for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching MFA state' -sev Debug

        $Cached = 0
        Get-CIPPMFAState -TenantFilter $TenantFilter | ForEach-Object { $Cached++; $_ } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MFAState' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $Cached MFA state records successfully" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache MFA state: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
