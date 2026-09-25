function Get-CIPPSharePointSharingReport {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        The SharePoint & OneDrive sharing report for a tenant, compiled from the CIPP reporting cache.
    .DESCRIPTION
        Rolls up the cached SharePointSharingLinks, SharePointSiteUsage and OneDriveUsage datasets into
        the shape the Sharing page (ListSharePointSharing) and the sharing PDF consume: environment,
        file and storage summaries per workload, link counts by classification, the sharing sprawl
        signals (anonymous links that allow editing, anonymous links with no expiry, folder-level
        external shares, password-protected links), the busiest sites, libraries and external
        recipients, and the individual link rows. No live Graph enumeration is performed; refresh the
        data by syncing those caches (ExecCIPPDBCache).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # Usage report values can arrive as numbers, strings or empty strings depending on the tenant.
    function ConvertTo-SafeDouble {
        param($Value)
        $Parsed = [double]0
        if ($null -ne $Value -and [double]::TryParse("$Value", [ref]$Parsed)) { return $Parsed }
        return [double]0
    }
    function Get-Total($Rows, [string]$Property) {
        ($Rows | ForEach-Object { ConvertTo-SafeDouble -Value $_.$Property } | Measure-Object -Sum).Sum
    }
    # Counts per key, largest first, as { <KeyName>; <ValueName> } rows for the charts and tables.
    function Get-RankedCount($Rows, [scriptblock]$Key, [string]$KeyName, [string]$ValueName, [int]$First = 0) {
        $Groups = @($Rows | Group-Object $Key | Where-Object { $_.Name } | Sort-Object -Property Count -Descending)
        if ($First -gt 0) { $Groups = @($Groups | Select-Object -First $First) }
        @($Groups | ForEach-Object { [PSCustomObject]@{ $KeyName = $_.Name; $ValueName = $_.Count } })
    }

    # --- Cached datasets, whether each has ever synced, and the oldest refresh across them ---
    $CacheData = @{}
    $CacheSynced = @{}
    $CacheTimestamps = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in @('SharePointSharingLinks', 'SharePointSiteUsage', 'OneDriveUsage')) {
        $CacheData[$Type] = try { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type) } catch { @() }
        $CountRow = try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly | Select-Object -First 1 } catch { $null }
        $CacheSynced[$Type] = [bool]$CountRow
        if ($CountRow.Timestamp) { $CacheTimestamps.Add($CountRow.Timestamp) }
    }
    $LastDataRefresh = $CacheTimestamps | Sort-Object | Select-Object -First 1

    # --- Environment summaries per workload. Teams-connected sites (rootWebTemplate 'Group' and 'Team Channel') are
    #     reported separately from the remaining SharePoint sites; OneDrive is per account. ---
    $TeamsSiteRows = @($CacheData['SharePointSiteUsage'] | Where-Object { $_.rootWebTemplate -in @('Group', 'Team Channel') })
    $SharePointSiteRows = @($CacheData['SharePointSiteUsage'] | Where-Object { $_.rootWebTemplate -notin @('Group', 'Team Channel') })
    $OneDriveRows = $CacheData['OneDriveUsage']

    # --- Sharing link rollups ---
    $Links = $CacheData['SharePointSharingLinks']
    $AnonymousLinks = @($Links | Where-Object { $_.classification -eq 'Anonymous' })
    $ExternalLinks = @($Links | Where-Object { $_.classification -eq 'External' })
    # 'write' and 'owner' both mean the recipient can change the content.
    $CanEdit = { param($Link) @($Link.roles) -contains 'write' -or @($Link.roles) -contains 'owner' }
    $SiteOf = { param($Link) [string]($Link.siteName ?? $Link.siteUrl) }
    # Who the tenant is sharing with, counted from named external recipients only: anonymous links
    # have no recipient and internal ones are not sprawl.
    $ExternalRecipients = @($ExternalLinks | ForEach-Object { @($_.sharedWith) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })
    $TopRecipients = @(Get-RankedCount $ExternalRecipients { $_ } 'recipient' 'links')

    $Body = [PSCustomObject]@{
        summary       = [PSCustomObject]@{
            sharePointSites         = $SharePointSiteRows.Count
            sharePointFiles         = [int64](Get-Total $SharePointSiteRows 'fileCount')
            sharePointStorageUsedGB = [math]::Round((Get-Total $SharePointSiteRows 'storageUsedInBytes') / 1GB, 2)
            teamsSites              = $TeamsSiteRows.Count
            teamsFiles              = [int64](Get-Total $TeamsSiteRows 'fileCount')
            teamsStorageUsedGB      = [math]::Round((Get-Total $TeamsSiteRows 'storageUsedInBytes') / 1GB, 2)
            oneDriveAccounts        = $OneDriveRows.Count
            oneDriveFiles           = [int64](Get-Total $OneDriveRows 'fileCount')
            oneDriveStorageUsedGB   = [math]::Round((Get-Total $OneDriveRows 'storageUsedInBytes') / 1GB, 2)
            totalLinks              = $Links.Count
            anonymousLinks          = $AnonymousLinks.Count
            externalLinks           = $ExternalLinks.Count
            internalLinks           = $Links.Count - $AnonymousLinks.Count - $ExternalLinks.Count
            itemsShared             = @($Links | Where-Object { $_.driveId -and $_.itemId } | ForEach-Object { "$($_.driveId)|$($_.itemId)" } | Sort-Object -Unique).Count
            anonymousEditLinks      = @($AnonymousLinks | Where-Object { & $CanEdit $_ }).Count
            neverExpiringAnonymous  = @($AnonymousLinks | Where-Object { -not $_.expirationDateTime }).Count
            # A share on a folder exposes everything below it, so it counts differently to a file share.
            folderShares            = @($Links | Where-Object { $_.itemType -eq 'Folder' -and $_.classification -in @('Anonymous', 'External') }).Count
            passwordProtectedLinks  = @($Links | Where-Object { $_.hasPassword -eq $true }).Count
            externalRecipients      = $TopRecipients.Count
            linksSynced             = $CacheSynced['SharePointSharingLinks']
            usageSynced             = ($CacheSynced['SharePointSiteUsage'] -or $CacheSynced['OneDriveUsage'])
            lastDataRefresh         = $LastDataRefresh
        }
        byScope       = @(Get-RankedCount $Links { [string]($_.classification ?? 'Internal') } 'scope' 'links')
        byLinkType    = @(Get-RankedCount $Links { [string]($_.linkType ?? 'link') } 'type' 'links')
        topSites      = @(Get-RankedCount $Links { & $SiteOf $_ } 'site' 'links' 10)
        topLibraries  = @(Get-RankedCount @($Links | Where-Object { $_.driveName }) { $Site = & $SiteOf $_; if ($Site) { "$Site / $($_.driveName)" } else { [string]$_.driveName } } 'library' 'links' 10)
        topRecipients = @($TopRecipients | Select-Object -First 10)
        links         = @($Links)
    }
    return $Body
}
