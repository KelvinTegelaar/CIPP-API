function Set-CIPPDBCacheManagedDeviceEncryptionStates {
    <#
    .SYNOPSIS
        Caches encryption states (BitLocker/FileVault) for managed devices in a tenant

    .PARAMETER TenantFilter
        The tenant to cache managed device encryption states for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed device encryption states' -sev Debug

        $ManagedDeviceEncryptionStates = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceEncryptionStates?$top=999' -tenantid $TenantFilter

        if ($ManagedDeviceEncryptionStates) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceEncryptionStates' -Data $ManagedDeviceEncryptionStates
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceEncryptionStates' -Data $ManagedDeviceEncryptionStates -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ManagedDeviceEncryptionStates.Count) managed device encryption states" -sev Debug
        }
        $ManagedDeviceEncryptionStates = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed device encryption states: $($_.Exception.Message)" -sev Error
    }
}
