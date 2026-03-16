function Set-CIPPDBCacheBitlockerKeys {
    <#
    .SYNOPSIS
        Caches all BitLocker recovery keys for a tenant

    .PARAMETER TenantFilter
        The tenant to cache BitLocker keys for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching BitLocker recovery keys' -sev Debug

        $BitlockerKeys = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys' -tenantid $TenantFilter
        if (!$BitlockerKeys) { $BitlockerKeys = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'BitlockerKeys' -Data $BitlockerKeys
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'BitlockerKeys' -Data $BitlockerKeys -Count
        $BitlockerKeys = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached BitLocker recovery keys successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache BitLocker recovery keys: $($_.Exception.Message)" -sev Error
    }
}
