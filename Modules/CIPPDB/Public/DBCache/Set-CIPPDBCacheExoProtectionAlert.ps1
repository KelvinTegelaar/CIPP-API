function Set-CIPPDBCacheExoProtectionAlert {
    <#
    .SYNOPSIS
        Caches Exchange Online / Purview protection alert policies

    .DESCRIPTION
        Calls Get-ProtectionAlert via the Security & Compliance PowerShell endpoint
        (requires the -Compliance switch on New-ExoRequest).

    .PARAMETER TenantFilter
        The tenant to cache protection alert data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange protection alerts' -sev Debug

        $ProtectionAlerts = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ProtectionAlert' -Compliance
        if ($ProtectionAlerts) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoProtectionAlert' -Data $ProtectionAlerts -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ProtectionAlerts.Count) protection alerts" -sev Debug
        }
        $ProtectionAlerts = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache protection alert data: $($_.Exception.Message)" -sev Error
    }
}
