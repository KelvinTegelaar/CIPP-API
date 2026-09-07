function Invoke-ListStorageCleanupScan {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Reads the hold-only StorageCleanupScan CIPPDB cache and rebuilds the scans map expected by
        the storage report cleanup opportunity helpers. No live enumeration — refresh via
        ExecCIPPDBCache Name=StorageCleanupScan. Report-private; not used by other List APIs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter ?? $Request.Query.TenantFilter ?? $Request.Body.TenantFilter

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required.' }
            })
    }

    try {
        $CacheRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageCleanupScan')
    } catch {
        $CacheRows = @()
    }

    $CleanupSynced = $false
    $LastDataRefresh = $null
    try {
        $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -CountsOnly | Select-Object -First 1
        if ($CountRow) { $CleanupSynced = $true }
        if ($CountRow.Timestamp) { $LastDataRefresh = $CountRow.Timestamp }
    } catch {}

    $SiteRows = @($CacheRows | Where-Object { $_.rowType -eq 'Site' })
    $LibraryRows = @($CacheRows | Where-Object { $_.rowType -eq 'Library' })

    $LibrariesBySiteUrl = @{}
    foreach ($Lib in $LibraryRows) {
        $Key = [string]$Lib.siteUrl
        if ([string]::IsNullOrWhiteSpace($Key)) { continue }
        $Key = $Key.TrimEnd('/')
        if (-not $LibrariesBySiteUrl.ContainsKey($Key)) {
            $LibrariesBySiteUrl[$Key] = [System.Collections.Generic.List[object]]::new()
        }
        $LibrariesBySiteUrl[$Key].Add([PSCustomObject]@{
                id                   = $Lib.libraryId
                name                 = $Lib.libraryName
                displayName          = $Lib.libraryDisplayName
                storageUsedInBytes   = $Lib.storageUsedInBytes
                versionEstimateBytes = $Lib.versionEstimateBytes
            })
    }

    $Scans = @{}
    $SitesScanned = 0
    $SitesSkipped = 0
    $LibrariesScanned = 0
    $SitesWithRecycle = 0

    foreach ($Site in $SiteRows) {
        $SitesScanned++
        if ($Site.collectionStatus -eq 'Skipped') { $SitesSkipped++ }

        $SiteUrl = [string]$Site.siteUrl
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { continue }
        $NormalizedUrl = $SiteUrl.TrimEnd('/')

        $Libraries = @()
        if ($LibrariesBySiteUrl.ContainsKey($NormalizedUrl)) {
            $Libraries = @($LibrariesBySiteUrl[$NormalizedUrl])
        }
        $LibrariesScanned += $Libraries.Count

        $Recycle = $null
        if ($null -ne $Site.recycleTotalBytes -or $null -ne $Site.recycleItemCount) {
            $SitesWithRecycle++
            $Recycle = [PSCustomObject]@{
                siteUrl          = $NormalizedUrl
                totalBytes       = $Site.recycleTotalBytes
                itemCount        = $Site.recycleItemCount
                firstStageBytes  = $Site.recycleFirstStageBytes
                firstStageCount  = $Site.recycleFirstStageCount
                secondStageBytes = $Site.recycleSecondStageBytes
                secondStageCount = $Site.recycleSecondStageCount
                capped           = $Site.recycleCapped
                scannedItems     = $Site.recycleScannedItems
            }
        }

        $ScanEntry = @{
            libraries = $Libraries
            recycle   = $Recycle
        }
        $Scans[$SiteUrl] = $ScanEntry
        if ($SiteUrl -ne $NormalizedUrl) {
            $Scans[$NormalizedUrl] = $ScanEntry
        }
    }

    # Libraries whose site row is missing (should not happen after a full store) still surface.
    foreach ($Key in $LibrariesBySiteUrl.Keys) {
        if ($Scans.ContainsKey($Key)) { continue }
        $Scans[$Key] = @{
            libraries = @($LibrariesBySiteUrl[$Key])
            recycle   = $null
        }
        $SitesScanned++
        $LibrariesScanned += $LibrariesBySiteUrl[$Key].Count
    }

    $Body = [PSCustomObject]@{
        summary = [PSCustomObject]@{
            cleanupSynced    = $CleanupSynced
            lastDataRefresh  = $LastDataRefresh
            sitesScanned     = $SitesScanned
            sitesSkipped     = $SitesSkipped
            librariesScanned = $LibrariesScanned
            sitesWithRecycle = $SitesWithRecycle
        }
        scans   = $Scans
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
