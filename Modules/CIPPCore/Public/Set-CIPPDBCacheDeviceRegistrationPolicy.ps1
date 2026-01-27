function Set-CIPPDBCacheDeviceRegistrationPolicy {
    <#
    .SYNOPSIS
        Caches device registration policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache device registration policy for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching device registration policy' -sev Debug

        $DeviceRegistrationPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $TenantFilter

        if ($DeviceRegistrationPolicy) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DeviceRegistrationPolicy' -Data @($DeviceRegistrationPolicy)
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached device registration policy successfully' -sev Debug
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache device registration policy: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
