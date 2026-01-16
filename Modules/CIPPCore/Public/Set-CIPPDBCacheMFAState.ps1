function Set-CIPPDBCacheMFAState {
    <#
    .SYNOPSIS
        Caches MFA state for a tenant

    .PARAMETER TenantFilter
        The tenant to cache MFA state for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching MFA state' -sev Info

        $MFAState = Get-CIPPMFAState -TenantFilter $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MFAState' -Data @($MFAState)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MFAState' -Data @($MFAState) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($MFAState.Count) MFA state records successfully" -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache MFA state: $($_.Exception.Message)" -sev Error
    }
}
