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

        if ($SPOTenant) {
            $SyncRestriction = [PSCustomObject]@{
                TenantRestrictionEnabled = $SPOTenant.TenantRestrictionEnabled
                AllowedDomainList        = $SPOTenant.AllowedDomainList
                BlockMacSync             = $SPOTenant.BlockMacSync
                ConditionalAccessPolicy  = $SPOTenant.ConditionalAccessPolicy
                TenantFilter             = $TenantFilter
            }
            $Data = @($SyncRestriction)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenantSyncClientRestriction' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenantSyncClientRestriction' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint sync client restriction' -sev Debug
        }
        $SPOTenant = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SPO sync client restriction: $($_.Exception.Message)" -sev Error
    }
}
