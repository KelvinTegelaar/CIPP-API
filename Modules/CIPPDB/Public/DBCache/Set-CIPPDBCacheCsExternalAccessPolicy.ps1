function Set-CIPPDBCacheCsExternalAccessPolicy {
    <#
    .SYNOPSIS
        Caches the Teams External Access Policy (Global)

    .DESCRIPTION
        Calls Get-CsExternalAccessPolicy via New-TeamsRequest and writes the
        result into the CippReportingDB under Type 'CsExternalAccessPolicy'.
        Used by CIS tests 8.2.1 (external domains) and 8.2.2 (unmanaged Teams users).

    .PARAMETER TenantFilter
        The tenant to cache the external access policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams External Access Policy' -sev Debug

        $ExternalAccess = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsExternalAccessPolicy' -CmdParams @{ Identity = 'Global' }

        if ($ExternalAccess) {
            $Data = @($ExternalAccess)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsExternalAccessPolicy' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsExternalAccessPolicy' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams External Access Policy' -sev Debug
        }
        $ExternalAccess = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams External Access Policy: $($_.Exception.Message)" -sev Error
    }
}
