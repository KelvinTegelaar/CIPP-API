function Set-CIPPDBCacheSecureScoreControlProfiles {
    <#
    .SYNOPSIS
        Caches secure score control profiles for a tenant

    .DESCRIPTION
        The control profiles are normally cached by Set-CIPPDBCacheSecureScore alongside the score
        history. This collector re-runs the same fetch and writes the same Type so the engine's
        on-miss Set-CIPPDBCache<Type> lookup resolves for 'SecureScoreControlProfiles'.

    .PARAMETER TenantFilter
        The tenant to cache secure score control profiles for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching secure score control profiles' -sev Debug

        $Profiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScoreControlProfiles' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles' -Data $Profiles -AddCount
        $Profiles = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached secure score control profiles successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache secure score control profiles: $($_.Exception.Message)" -sev Error
    }
}
