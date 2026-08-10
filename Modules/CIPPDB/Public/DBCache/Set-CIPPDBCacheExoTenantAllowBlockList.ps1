function Set-CIPPDBCacheExoTenantAllowBlockList {
    <#
    .SYNOPSIS
        Caches Exchange Online Tenant Allow/Block List items

    .PARAMETER TenantFilter
        The tenant to cache tenant allow/block list for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Tenant Allow/Block List items' -sev Debug

        # Every list type in one batched request, ListType-stamped. Same helper the live
        # ListTenantAllowBlockList path uses, so the cache and the live view agree.
        $AllItems = @(Get-CIPPTenantAllowBlockListItems -TenantFilter $TenantFilter)

        if ($AllItems.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data $AllItems -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllItems.Count) Tenant Allow/Block List items" -sev Debug
        } else {
            # Even if empty, store an empty array so test knows cache was populated
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data @() -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached empty Tenant Allow/Block List' -sev Debug
        }
        $AllItems = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Tenant Allow/Block List: $($_.Exception.Message)" -sev Error
    }
}
