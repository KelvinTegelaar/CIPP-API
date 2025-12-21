function Set-CIPPDBCacheSecureScore {
    <#
    .SYNOPSIS
        Caches secure score history (last 14 days) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache secure score for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching secure score' -sev Info
        $SecureScore = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScores?$top=14' -tenantid $TenantFilter -noPagination $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScore' -Data $SecureScore
        $SecureScore = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached secure score successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache secure score: $($_.Exception.Message)" -sev Error
    }
}
