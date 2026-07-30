function Invoke-ListSharePointSharing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Compiles the SharePoint & OneDrive sharing report for a tenant from CACHED data in the
        CIPP reporting database (SharePointSharingLinks, SharePointSiteUsage, OneDriveUsage).
        No live Graph enumeration is performed - refresh the data by syncing those caches
        (ExecCIPPDBCache). Returns environment/file/storage summaries per workload, sharing link
        counts by classification, chart datasets and the individual sharing link rows.

        Also rolls up the sharing sprawl signals held in the same rows: anonymous links that allow
        editing, anonymous links with no expiry, folder-level external shares (one share exposes
        everything below it), and the busiest libraries and external recipients.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    # Usage report values can arrive as numbers, strings or empty strings depending on the tenant.
    function ConvertTo-SafeDouble {
        param($Value)
        $Parsed = [double]0
        if ($null -ne $Value -and [double]::TryParse("$Value", [ref]$Parsed)) { return $Parsed }
        return [double]0
    }

    # --- Cached datasets from the CIPP reporting database ---
    $CacheTypes = @('SharePointSharingLinks', 'SharePointSiteUsage', 'OneDriveUsage')
    $CacheData = @{}
    $CacheSynced = @{}
    $CacheTimestamps = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in $CacheTypes) {
        try {
            $CacheData[$Type] = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type)
        } catch {
            $CacheData[$Type] = @()
        }
        $CacheSynced[$Type] = $false
        try {
            $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly | Select-Object -First 1
            if ($CountRow) { $CacheSynced[$Type] = $true }
            if ($CountRow.Timestamp) { $CacheTimestamps.Add($CountRow.Timestamp) }
        } catch {}
    }
    $LastDataRefresh = $CacheTimestamps | Sort-Object | Select-Object -First 1

    # --- Environment summaries per workload. Teams-connected sites (rootWebTemplate 'Group')
    #     are reported separately from the remaining SharePoint sites; OneDrive is per account. ---
    $SharePointSites = 0; $SharePointFiles = [int64]0; $SharePointStorage = [double]0
    $TeamsSites = 0; $TeamsFiles = [int64]0; $TeamsStorage = [double]0
    foreach ($Site in $CacheData['SharePointSiteUsage']) {
        $Files = [int64](ConvertTo-SafeDouble -Value $Site.fileCount)
        $Storage = ConvertTo-SafeDouble -Value $Site.storageUsedInBytes
        if ($Site.rootWebTemplate -eq 'Group') {
            $TeamsSites++; $TeamsFiles += $Files; $TeamsStorage += $Storage
        } else {
            $SharePointSites++; $SharePointFiles += $Files; $SharePointStorage += $Storage
        }
    }

    $OneDriveAccounts = 0; $OneDriveFiles = [int64]0; $OneDriveStorage = [double]0
    foreach ($Account in $CacheData['OneDriveUsage']) {
        $OneDriveAccounts++
        $OneDriveFiles += [int64](ConvertTo-SafeDouble -Value $Account.fileCount)
        $OneDriveStorage += ConvertTo-SafeDouble -Value $Account.storageUsedInBytes
    }

    # --- Sharing link rollups ---
    $Links = $CacheData['SharePointSharingLinks']
    $AnonymousLinks = 0; $ExternalLinks = 0; $InternalLinks = 0
    $ByScope = @{}
    $ByLinkType = @{}
    $BySite = @{}
    $ByLibrary = @{}
    $ByRecipient = @{}
    $SharedItemIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # Sprawl risk signals, derived from the same cached rows.
    $AnonymousEditLinks = 0; $NeverExpiringAnonymousLinks = 0; $FolderShares = 0; $PasswordProtectedLinks = 0
    foreach ($Link in $Links) {
        switch ($Link.classification) {
            'Anonymous' { $AnonymousLinks++ }
            'External' { $ExternalLinks++ }
            default { $InternalLinks++ }
        }
        $Scope = [string]($Link.classification ?? 'Internal')
        $ByScope[$Scope] = [int]($ByScope[$Scope] ?? 0) + 1
        $Type = [string]($Link.linkType ?? 'link')
        $ByLinkType[$Type] = [int]($ByLinkType[$Type] ?? 0) + 1
        $SiteName = [string]($Link.siteName ?? $Link.siteUrl)
        if ($SiteName) { $BySite[$SiteName] = [int]($BySite[$SiteName] ?? 0) + 1 }
        if ($Link.driveName) {
            $LibraryLabel = if ($SiteName) { "$SiteName / $($Link.driveName)" } else { [string]$Link.driveName }
            $ByLibrary[$LibraryLabel] = [int]($ByLibrary[$LibraryLabel] ?? 0) + 1
        }
        if ($Link.driveId -and $Link.itemId) { [void]$SharedItemIds.Add("$($Link.driveId)|$($Link.itemId)") }

        # 'write' and 'owner' both mean the recipient can change the content.
        $CanEdit = @($Link.roles) -contains 'write' -or @($Link.roles) -contains 'owner'
        if ($Link.classification -eq 'Anonymous') {
            if ($CanEdit) { $AnonymousEditLinks++ }
            if (-not $Link.expirationDateTime) { $NeverExpiringAnonymousLinks++ }
        }
        # A share on a folder exposes everything below it, so it counts differently to a file share.
        if ($Link.itemType -eq 'Folder' -and $Link.classification -in @('Anonymous', 'External')) { $FolderShares++ }
        if ($Link.hasPassword -eq $true) { $PasswordProtectedLinks++ }

        # Who the tenant is sharing with, counted from named external recipients only:
        # anonymous links have no recipient and internal ones are not sprawl.
        if ($Link.classification -eq 'External') {
            foreach ($Recipient in @($Link.sharedWith)) {
                if ([string]::IsNullOrWhiteSpace($Recipient)) { continue }
                $ByRecipient[[string]$Recipient] = [int]($ByRecipient[[string]$Recipient] ?? 0) + 1
            }
        }
    }

    $Body = [PSCustomObject]@{
        summary       = [PSCustomObject]@{
            sharePointSites         = $SharePointSites
            sharePointFiles         = $SharePointFiles
            sharePointStorageUsedGB = [math]::Round($SharePointStorage / 1GB, 2)
            teamsSites              = $TeamsSites
            teamsFiles              = $TeamsFiles
            teamsStorageUsedGB      = [math]::Round($TeamsStorage / 1GB, 2)
            oneDriveAccounts        = $OneDriveAccounts
            oneDriveFiles           = $OneDriveFiles
            oneDriveStorageUsedGB   = [math]::Round($OneDriveStorage / 1GB, 2)
            totalLinks              = @($Links).Count
            anonymousLinks          = $AnonymousLinks
            externalLinks           = $ExternalLinks
            internalLinks           = $InternalLinks
            itemsShared             = $SharedItemIds.Count
            anonymousEditLinks      = $AnonymousEditLinks
            neverExpiringAnonymous  = $NeverExpiringAnonymousLinks
            folderShares            = $FolderShares
            passwordProtectedLinks  = $PasswordProtectedLinks
            externalRecipients      = $ByRecipient.Count
            linksSynced             = $CacheSynced['SharePointSharingLinks']
            usageSynced             = ($CacheSynced['SharePointSiteUsage'] -or $CacheSynced['OneDriveUsage'])
            lastDataRefresh         = $LastDataRefresh
        }
        byScope       = @($ByScope.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [PSCustomObject]@{ scope = $_.Key; links = $_.Value } })
        byLinkType    = @($ByLinkType.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [PSCustomObject]@{ type = $_.Key; links = $_.Value } })
        topSites      = @($BySite.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { [PSCustomObject]@{ site = $_.Key; links = $_.Value } })
        topLibraries  = @($ByLibrary.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { [PSCustomObject]@{ library = $_.Key; links = $_.Value } })
        topRecipients = @($ByRecipient.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object { [PSCustomObject]@{ recipient = $_.Key; links = $_.Value } })
        links         = @($Links)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
