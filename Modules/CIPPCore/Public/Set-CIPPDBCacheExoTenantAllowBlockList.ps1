function Set-CIPPDBCacheExoTenantAllowBlockList {
    <#
    .SYNOPSIS
        Caches Exchange Online Tenant Allow/Block List items

    .PARAMETER TenantFilter
        The tenant to cache tenant allow/block list for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Tenant Allow/Block List items' -sev Info

        $SenderItems = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = 'Sender' }
        $UrlItems = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = 'Url' }
        $FileHashItems = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = 'FileHash' }

        # Combine all list types into a single collection
        $AllItems = @()
        if ($SenderItems) {
            $AllItems += $SenderItems
        }
        if ($UrlItems) {
            $AllItems += $UrlItems
        }
        if ($FileHashItems) {
            $AllItems += $FileHashItems
        }

        if ($AllItems.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data $AllItems
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data $AllItems -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllItems.Count) Tenant Allow/Block List items" -sev Info
        } else {
            # Even if empty, store an empty array so test knows cache was populated
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data @()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList' -Data @() -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached empty Tenant Allow/Block List' -sev Info
        }
        $SenderItems = $null
        $UrlItems = $null
        $FileHashItems = $null
        $AllItems = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Tenant Allow/Block List: $($_.Exception.Message)" -sev Error
    }
}
