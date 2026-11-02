function ConvertTo-CIPPSharePointSiteUsagePayload {
    <#
    .SYNOPSIS
        Maps a SharePoint site listing row and usage row to the Invoke-ListSites payload shape.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Site,

        $SiteUsage,

        [string]$Tenant,

        $CacheTimestamp
    )

    $StorageUsedInGigabytes = if ($SiteUsage -and $null -ne $SiteUsage.storageUsedInBytes) {
        [math]::Round([double]$SiteUsage.storageUsedInBytes / 1GB, 2)
    } else { $null }

    $StorageAllocatedInGigabytes = if ($SiteUsage -and $null -ne $SiteUsage.storageAllocatedInBytes) {
        [math]::Round([double]$SiteUsage.storageAllocatedInBytes / 1GB, 2)
    } else { $null }

    $ArchiveGb = if ($null -ne $Site.archivedFileDiskUsedBytes) {
        [math]::Round([double]$Site.archivedFileDiskUsedBytes / 1GB, 2)
    } else { $null }

    $ReportItem = [PSCustomObject]@{
        siteId                        = $Site.sharepointIds.siteId
        webId                         = $Site.sharepointIds.webId
        createdDateTime               = $Site.createdDateTime
        displayName                   = $Site.displayName
        webUrl                        = $Site.webUrl
        ownerDisplayName              = if ($SiteUsage) { $SiteUsage.ownerDisplayName } else { $null }
        ownerPrincipalName            = if ($SiteUsage) { $SiteUsage.ownerPrincipalName } else { $null }
        lastActivityDate              = if ($SiteUsage) { $SiteUsage.lastActivityDate } else { $null }
        fileCount                     = if ($SiteUsage) { $SiteUsage.fileCount } else { $null }
        storageUsedInGigabytes        = $StorageUsedInGigabytes
        storageAllocatedInGigabytes   = $StorageAllocatedInGigabytes
        storageUsedInBytes            = if ($SiteUsage) { $SiteUsage.storageUsedInBytes } else { $null }
        storageAllocatedInBytes       = if ($SiteUsage) { $SiteUsage.storageAllocatedInBytes } else { $null }
        rootWebTemplate               = if ($SiteUsage) { $SiteUsage.rootWebTemplate } else { $null }
        reportRefreshDate             = if ($SiteUsage) { $SiteUsage.reportRefreshDate } else { $null }
        archivedFileDiskUsedBytes     = $Site.archivedFileDiskUsedBytes
        archivedFileDiskUsedGigabytes = $ArchiveGb
        allowFileArchive              = $Site.allowFileArchive
        AutoMapUrl                    = $Site.AutoMapUrl
    }

    if ($Tenant) {
        $ReportItem | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
    }

    if ($CacheTimestamp) {
        $ReportItem | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
    }

    return $ReportItem
}
