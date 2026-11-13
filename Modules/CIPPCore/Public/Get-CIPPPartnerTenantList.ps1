function Get-CIPPPartnerTenantList {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Returns non-secret metadata for the configured partner tenants.
    .DESCRIPTION
    Exported wrapper for HTTP endpoints outside CIPPCore. Metadata only - ids, names, flags.
    Listed in the scheduler blocklist like Get-Tenants.
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeDisabled
    )

    Get-CIPPPartnerTenant -IncludeDisabled:$IncludeDisabled | ForEach-Object {
        [PSCustomObject]@{
            partnerTenantId = "$($_.RowKey)"
            displayName     = "$($_.displayName)"
            IsPrimary       = [bool]$_.IsPrimary
            Enabled         = $_.Enabled -ne $false
        }
    }
}
