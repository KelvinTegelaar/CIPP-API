function Push-StoreSharePointSharingLinks {
    <#
    .SYNOPSIS
        Post-execution function that aggregates per-site sharing links and writes the cache.

    .DESCRIPTION
        Collects the row sets returned by every Push-DBCacheSharePointSiteSharingLinks activity and
        writes them to the CIPP reporting database as a single SharePointSharingLinks dataset (full
        replace with count). Writing once from this serial step avoids the {Type}-Count race that
        parallel appenders would cause.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter

    try {
        $AllRows = [System.Collections.Generic.List[object]]::new()
        foreach ($SiteResult in $Item.Results) {
            foreach ($Row in @($SiteResult)) {
                if ($Row -and $Row.id) { $AllRows.Add($Row) }
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSharingLinks' -Data @($AllRows) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllRows.Count) SharePoint/OneDrive sharing links across $(@($Item.Results).Count) sites" -sev Info
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store SharePoint sharing links: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
