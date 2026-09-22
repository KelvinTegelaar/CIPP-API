function Push-DBCacheStorageCleanupScanBatch {
    <#
    .SYNOPSIS
        Collects library version estimates and recycle-bin totals for a batch of SharePoint sites.

    .DESCRIPTION
        Processes up to 20 site seeds per activity. Each site is wrapped in its own try/catch so a
        batch of N sites always returns exactly N site results - Push-StoreStorageCleanupScan
        relies on that to verify completeness before it replaces the cache.

        Per site (mirrors ListSiteBrowser library drill-in + ListSiteRecycleBinSummary):
        - Graph lists for documentLibrary / webPageLibrary
        - SPO StorageMetrics for versionEstimateBytes
        - Aggregate recycle bin sizes (no item titles or paths)

        Two row types are emitted, discriminated by rowType:
        - Site     one per scanned site (Full or Skipped); carries recycle aggregates
        - Library  one per visible document/page library when collection succeeded

        collectionStatus:
        - Full     libraries were collected; recycle fields may still be null if recycle failed
        - Skipped  site-level collection failed; no Library rows

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $BatchNumber = $Item.BatchNumber
    $SiteSeeds = @($Item.Sites)

    function New-CleanupSiteRow {
        param(
            $SiteSeed,
            [string]$Status,
            [string]$ErrorMessage,
            [int]$LibrariesScanned,
            [string]$CollectedAt,
            $Recycle
        )
        [PSCustomObject]@{
            rowType                = 'Site'
            id                     = "$($SiteSeed.id)_site"
            siteId                 = $SiteSeed.id
            displayName            = $SiteSeed.displayName
            siteUrl                = $SiteSeed.webUrl
            collectionStatus       = $Status
            collectionError        = $ErrorMessage
            librariesScanned       = $LibrariesScanned
            recycleTotalBytes      = $Recycle.totalBytes
            recycleItemCount       = $Recycle.itemCount
            recycleFirstStageBytes = $Recycle.firstStageBytes
            recycleFirstStageCount = $Recycle.firstStageCount
            recycleSecondStageBytes = $Recycle.secondStageBytes
            recycleSecondStageCount = $Recycle.secondStageCount
            recycleCapped          = $Recycle.capped
            recycleScannedItems    = $Recycle.scannedItems
            collectedAt            = $CollectedAt
        }
    }

    function Get-CIPPRecycleBinSummary {
        param(
            [string]$TenantFilter,
            [string]$SiteUrl,
            [string]$Scope,
            $JsonAccept,
            [int]$MaxItems = 5000
        )
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
        $FirstCount = [int64]0
        $FirstBytes = [int64]0
        $SecondCount = [int64]0
        $SecondBytes = [int64]0
        $Seen = 0
        $Capped = $false
        $NextUri = "$BaseUri/site/RecycleBin?`$select=Id,Size,ItemState&`$top=500&`$orderby=DeletedDate desc"

        while ($NextUri) {
            $Page = New-GraphGetRequest -uri $NextUri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
            $Items = @()
            $NextLink = $null
            if ($null -ne $Page.value) {
                $Items = @($Page.value)
                $NextLink = $Page.'@odata.nextLink'
            } elseif ($Page -is [System.Array]) {
                $Items = @($Page)
            } elseif ($Page.PSObject.Properties.Name -contains 'Id') {
                $Items = @($Page)
            }

            foreach ($BinItem in $Items) {
                if ($Seen -ge $MaxItems) {
                    $Capped = $true
                    break
                }
                $Seen++
                $Size = 0
                try { $Size = [int64][double]$BinItem.Size } catch { $Size = 0 }
                $State = 0
                try { $State = [int]$BinItem.ItemState } catch { $State = 0 }
                if ($State -eq 2) {
                    $SecondCount++
                    $SecondBytes += $Size
                } else {
                    $FirstCount++
                    $FirstBytes += $Size
                }
            }

            if ($Capped -or [string]::IsNullOrWhiteSpace($NextLink)) { break }
            $NextUri = $NextLink
        }

        return [PSCustomObject]@{
            siteUrl          = $SiteUrl.TrimEnd('/')
            itemCount        = $FirstCount + $SecondCount
            totalBytes       = $FirstBytes + $SecondBytes
            firstStageCount  = $FirstCount
            firstStageBytes  = $FirstBytes
            secondStageCount = $SecondCount
            secondStageBytes = $SecondBytes
            capped           = $Capped
            scannedItems     = $Seen
        }
    }

    $SiteResults = [System.Collections.Generic.List[object]]::new()

    try {
        Write-Information "Processing StorageCleanupScan batch $BatchNumber for tenant $TenantFilter with $($SiteSeeds.Count) sites"

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $SpoScope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }

        foreach ($SiteSeed in $SiteSeeds) {
            $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
            $LibraryRows = [System.Collections.Generic.List[object]]::new()
            try {
                $SiteId = $SiteSeed.id
                $SiteUrl = $SiteSeed.webUrl
                if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
                    throw 'Site webUrl is required'
                }

                $SiteSegment = $SiteId
                if ([string]::IsNullOrWhiteSpace($SiteSegment)) {
                    $ParsedUrl = [System.Uri]$SiteUrl
                    $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                        $ParsedUrl.Host
                    } else {
                        "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
                    }
                }

                $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
                $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteSegment/lists?`$select=id,displayName,name,webUrl,list,createdDateTime" -tenantid $TenantFilter -asapp $true
                $Libraries = @($Lists | Where-Object { $_.list.hidden -ne $true -and $_.list.template -in @('documentLibrary', 'webPageLibrary') })

                foreach ($List in $Libraries) {
                    $StorageUsed = $null
                    $FileCount = $null
                    $FileStreamSize = $null
                    $MetadataSize = $null
                    $VersionEstimate = $null
                    try {
                        $Metrics = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$($List.id)')/RootFolder?`$select=StorageMetrics&`$expand=StorageMetrics" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                        $TotalSize = ConvertTo-SPOAdminListInt64 -Raw $Metrics.StorageMetrics.TotalSize
                        $FileStreamSize = ConvertTo-SPOAdminListInt64 -Raw $Metrics.StorageMetrics.TotalFileStreamSize
                        $MetadataSize = ConvertTo-SPOAdminListInt64 -Raw $Metrics.StorageMetrics.MetadataSize
                        $FileCount = ConvertTo-SPOAdminListInt64 -Raw $Metrics.StorageMetrics.TotalFileCount
                        $StorageUsed = $TotalSize
                        if ($null -ne $TotalSize) {
                            $Tip = if ($null -ne $FileStreamSize) { $FileStreamSize } else { [int64]0 }
                            $Meta = if ($null -ne $MetadataSize) { $MetadataSize } else { [int64]0 }
                            $VersionEstimate = [Math]::Max([int64]0, $TotalSize - $Tip - $Meta)
                        }
                    } catch {
                        $StorageUsed = $null
                        $FileCount = $null
                        $FileStreamSize = $null
                        $MetadataSize = $null
                        $VersionEstimate = $null
                    }

                    $LibraryRows.Add([PSCustomObject]@{
                            rowType               = 'Library'
                            id                    = "$($SiteId)_$($List.id)"
                            siteId                = $SiteId
                            siteUrl               = $SiteUrl
                            libraryId             = $List.id
                            libraryName           = $List.name
                            libraryDisplayName    = $List.displayName
                            storageUsedInBytes    = $StorageUsed
                            versionEstimateBytes  = $VersionEstimate
                            fileStreamSizeInBytes = $FileStreamSize
                            metadataSizeInBytes   = $MetadataSize
                            fileCount             = $FileCount
                            template              = $List.list.template
                            webUrl                = $List.webUrl
                            collectedAt           = $CollectedAt
                        })
                }

                $Recycle = $null
                try {
                    $Recycle = Get-CIPPRecycleBinSummary -TenantFilter $TenantFilter -SiteUrl $SiteUrl -Scope $SpoScope -JsonAccept $JsonAccept
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "StorageCleanupScan: recycle summary failed for '$SiteUrl': $($_.Exception.Message)" -sev Warning
                    $Recycle = $null
                }

                $SiteResults.Add([PSCustomObject]@{
                        SiteId           = $SiteId
                        CollectionStatus = 'Full'
                        SiteRow          = (New-CleanupSiteRow -SiteSeed $SiteSeed -Status 'Full' -ErrorMessage $null -LibrariesScanned $LibraryRows.Count -CollectedAt $CollectedAt -Recycle $Recycle)
                        Rows             = @($LibraryRows)
                    })

            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "StorageCleanupScan: collection failed for '$($SiteSeed.webUrl)': $($_.Exception.Message)" -sev Warning
                $SiteResults.Add([PSCustomObject]@{
                        SiteId           = $SiteSeed.id
                        CollectionStatus = 'Skipped'
                        SiteRow          = (New-CleanupSiteRow -SiteSeed $SiteSeed -Status 'Skipped' -ErrorMessage $_.Exception.Message -LibrariesScanned 0 -CollectedAt $CollectedAt -Recycle $null)
                        Rows             = @()
                    })
            }
        }

        if ($SiteResults.Count -ne $SiteSeeds.Count) {
            throw "Batch $BatchNumber invariant violated: expected $($SiteSeeds.Count) site results, got $($SiteResults.Count)"
        }

        return [PSCustomObject]@{
            BatchNumber = $BatchNumber
            Sites       = @($SiteResults)
        }

    } catch {
        $ErrorMsg = "Failed StorageCleanupScan batch $BatchNumber for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
