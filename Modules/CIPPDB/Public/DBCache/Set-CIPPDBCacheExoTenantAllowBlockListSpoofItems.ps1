function Set-CIPPDBCacheExoTenantAllowBlockListSpoofItems {
    <#
    .SYNOPSIS
        Caches Exchange Online Tenant Allow/Block List Spoof Items

    .DESCRIPTION
        Caches Get-TenantAllowBlockListSpoofItems output (Identity, SendingInfrastructure,
        SpoofType, Action). Spoof items live on a separate cmdlet from the entry-based
        allow/block lists cached by Set-CIPPDBCacheExoTenantAllowBlockList, hence the
        dedicated collector and type.

    .PARAMETER TenantFilter
        The tenant to cache spoof items for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Tenant Allow/Block List Spoof Items' -sev Debug

        $SpoofItems = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TenantAllowBlockListSpoofItems')

        $Items = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($SpoofItem in $SpoofItems) {
            $Items.Add([PSCustomObject]@{
                    Identity              = $SpoofItem.Identity
                    SendingInfrastructure = $SpoofItem.SendingInfrastructure
                    SpoofType             = $SpoofItem.SpoofType
                    Action                = $SpoofItem.Action
                })
        }

        # Even if empty, store an empty array so tests know the cache was populated
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockListSpoofItems' -Data @($Items) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Items.Count) Tenant Allow/Block List Spoof Items" -sev Debug
        $SpoofItems = $null
        $Items = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Tenant Allow/Block List Spoof Items: $($_.Exception.Message)" -sev Error
    }
}
