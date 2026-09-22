function Set-CIPPDBCacheCsExternalAccessPolicy {
    <#
    .SYNOPSIS
        Caches the Teams External Access Policy (Global)

    .DESCRIPTION
        Calls Get-CsExternalAccessPolicy via New-TeamsRequestV2 and writes the
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

        $ExternalAccess = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type 'ExternalAccessPolicy' -Action Get -Identity 'Global'

        if ($ExternalAccess) {
            $Data = @($ExternalAccess)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsExternalAccessPolicy' -Data $Data -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams External Access Policy' -sev Debug
        } else {
            # The request succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CsExternalAccessPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Teams External Access Policies (none found)' -sev Debug
        }
        $ExternalAccess = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams External Access Policy: $($_.Exception.Message)" -sev Error
    }
}
