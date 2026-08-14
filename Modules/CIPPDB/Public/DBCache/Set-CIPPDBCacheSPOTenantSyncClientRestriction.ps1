function Set-CIPPDBCacheSPOTenantSyncClientRestriction {
    <#
    .SYNOPSIS
        Caches SharePoint Online tenant sync client restriction configuration

    .DESCRIPTION
        Queries the SPO admin endpoint for the tenant sync client restriction
        properties (TenantRestrictionEnabled, AllowedDomainList, BlockMacSync)
        and writes the result into the CippReportingDB under Type
        'SPOTenantSyncClientRestriction'. These properties are part of the
        SPOTenant object returned by Get-CIPPSPOTenant, so we surface them as
        their own cache type for clarity and to mirror the cmdlet boundary in
        Get-SPOTenantSyncClientRestriction.

    .PARAMETER TenantFilter
        The tenant to cache the sync restriction configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint sync client restriction' -sev Debug

        $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter

        # An empty response is a failure too - see Set-CIPPDBCacheSPOTenant.
        if (-not $SPOTenant) {
            throw 'The SharePoint admin endpoint returned no tenant configuration'
        }

        $SyncRestriction = [PSCustomObject]@{
            TenantRestrictionEnabled = $SPOTenant.TenantRestrictionEnabled
            AllowedDomainList        = $SPOTenant.AllowedDomainList
            BlockMacSync             = $SPOTenant.BlockMacSync
            ConditionalAccessPolicy  = $SPOTenant.ConditionalAccessPolicy
            TenantFilter             = $TenantFilter
        }
        $Data = @($SyncRestriction)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenantSyncClientRestriction' -Data $Data -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint sync client restriction' -sev Debug
        $SPOTenant = $null

    } catch {
        # Missing SharePoint consent is a tenant state, not a collection failure - see
        # Set-CIPPDBCacheSPOTenant.
        if ($_.Exception.Data['SPOAccessDenied']) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $_.Exception.Message -sev Warning
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SPO sync client restriction: $($_.Exception.Message)" -sev Error
        # Anything else is unexpected, so let the caller count it.
        throw
    }
}
