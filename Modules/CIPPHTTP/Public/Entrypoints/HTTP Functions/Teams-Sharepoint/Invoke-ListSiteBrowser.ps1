function Invoke-ListSiteBrowser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        SharePoint site browser listing (sites only — not OneDrive).
        Root: Get-CIPPSPOAdminListData (SPO.Tenant/RenderAdminListData, Active sites catalog) —
        StorageUsed / NumOfFiles / TemplateName in one paged call.
        Graph getAllSites joins only for Graph site.id (drill-in).
        With SiteId/SiteUrl: root document/page libraries (Graph lists + SPO StorageMetrics).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    # Match other SharePoint endpoints: query keys may arrive as TenantFilter or tenantFilter.
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter ?? $Request.Body.TenantFilter ?? $Request.Body.tenantFilter
    $SiteId = $Request.Query.SiteId ?? $Request.Body.SiteId
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = 'tenantFilter is required.' }
            })
    }

    function ConvertTo-StorageUsedBytes {
        param($Raw)
        if ($null -eq $Raw -or $Raw -eq '') { return $null }
        $Clean = ([string]$Raw).Replace(',', '').Trim()
        if ($Clean -eq '') { return $null }
        try { return [int64][double]$Clean } catch { return $null }
    }

    function ConvertTo-NullableInt64 {
        param($Raw)
        if ($null -eq $Raw -or $Raw -eq '') { return $null }
        $Clean = ([string]$Raw).Replace(',', '').Trim()
        if ($Clean -eq '') { return $null }
        try { return [int64][double]$Clean } catch { return $null }
    }

    function ConvertTo-SiteTypeLabel {
        param(
            [string]$Template,
            [string]$ItemType,
            [string]$LibraryTemplate
        )
        if ($ItemType -eq 'library') {
            if ($LibraryTemplate -eq 'webPageLibrary') { return 'Site pages' }
            if ($LibraryTemplate -eq 'documentLibrary') { return 'Document library' }
            return $LibraryTemplate ? $LibraryTemplate : 'Library'
        }
        if ([string]::IsNullOrWhiteSpace($Template)) { return 'Site' }

        # Admin/usage templates are usually "GROUP#0", "STS#3", etc. — strip the config id.
        $Normalized = ($Template -split '#')[0].Trim()

        switch -Regex ($Normalized) {
            '^(?i)Group$' { return 'Team site' }
            '^(?i)Team\s*Site$' { return 'Team site' }
            '(?i)SitePagePublishing|Site Page Publishing' { return 'Communication site' }
            '^(?i)STS' { return 'Team site (classic)' }
            '(?i)Redirect' { return 'Redirect site' }
            '^(?i)APPCATALOG$' { return 'App catalog' }
            default { return $Normalized }
        }
    }

    function Test-CIPPSiteBrowserLeaveOut {
        param(
            [string]$Name,
            [string]$WebUrl,
            [string[]]$SitesToLeaveOut
        )
        $SitePath = $null
        $SitePathLeaf = $null
        if (-not [string]::IsNullOrWhiteSpace($WebUrl)) {
            try {
                $SitePath = ([System.Uri]$WebUrl).AbsolutePath.Trim('/')
                if (-not [string]::IsNullOrWhiteSpace($SitePath)) {
                    $SitePathLeaf = $SitePath.Split('/')[-1]
                }
            } catch {
                $SitePath = $null
                $SitePathLeaf = $null
            }
        }
        foreach ($LeaveOutName in $SitesToLeaveOut) {
            if (
                ([string]::Equals($Name, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                ([string]::Equals($SitePath, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase)) -or
                ([string]::Equals($SitePathLeaf, $LeaveOutName, [System.StringComparison]::OrdinalIgnoreCase))
            ) {
                return $true
            }
        }
        return $false
    }

    try {
        $SiteInfo = $null
        $StorageStatus = $null
        $HasSite = -not [string]::IsNullOrWhiteSpace($SiteId) -or -not [string]::IsNullOrWhiteSpace($SiteUrl)

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $SpoScope = "$($SharePointInfo.SharePointUrl)/.default"
        $AdminUrl = $SharePointInfo.AdminUrl
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }

        $SitesToLeaveOut = @(
            'search'
            'contentTypeHub'
            'appcatalog'
            'portals/hub'
            'portals/community'
        )

        if (-not $HasSite) {
            $Results = [System.Collections.Generic.List[object]]::new()
            # Active sites catalog via RenderAdminListData (defaults match admin UI filters).
            $AdminRows = @(Get-CIPPSPOAdminListData -TenantFilter $TenantFilter -AdminUrl $AdminUrl -Type SharePoint)
            $StorageStatus = 'admin'

            # Graph join for site.id only (drill-in).
            $GraphBulk = New-GraphBulkRequest -tenantid $TenantFilter -Requests @(
                @{
                    id     = 'listAllSites'
                    method = 'GET'
                    url    = "sites/getAllSites?`$filter=isPersonalSite eq false&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,webUrl,siteCollection,sharepointIds&`$top=999"
                }
            ) -asapp $true
            $SitesResponse = @($GraphBulk | Where-Object { $_.id -eq 'listAllSites' }) | Select-Object -First 1
            if ($null -eq $SitesResponse) {
                throw 'getAllSites response missing from Graph bulk batch'
            }
            if ($SitesResponse.status -and $SitesResponse.status -ne 200) {
                throw ($SitesResponse.body.error.message ?? "getAllSites failed with status $($SitesResponse.status)")
            }
            $GraphSites = @($SitesResponse.body.value)
            $GraphBySiteId = @{}
            $GraphByWebUrl = @{}
            foreach ($GraphSite in $GraphSites) {
                if ($null -eq $GraphSite) { continue }
                $Guid = [string]$GraphSite.sharepointIds.siteId
                if (-not [string]::IsNullOrWhiteSpace($Guid)) {
                    $GraphBySiteId[$Guid.Trim('{}').ToLowerInvariant()] = $GraphSite
                }
                if (-not [string]::IsNullOrWhiteSpace($GraphSite.webUrl)) {
                    $GraphByWebUrl[$GraphSite.webUrl.TrimEnd('/').ToLowerInvariant()] = $GraphSite
                }
            }

            foreach ($Row in $AdminRows) {
                $RowUrl = [string]$Row.SiteUrl
                $RowTitle = [string]$Row.Title
                $RowSiteIdRaw = [string]$Row.SiteId
                $RowSiteId = $RowSiteIdRaw.Trim('{}')
                $NameLeaf = $null
                if (-not [string]::IsNullOrWhiteSpace($RowUrl)) {
                    try {
                        $NameLeaf = ([System.Uri]$RowUrl).AbsolutePath.Trim('/').Split('/')[-1]
                    } catch { $NameLeaf = $null }
                }
                if (Test-CIPPSiteBrowserLeaveOut -Name $NameLeaf -WebUrl $RowUrl -SitesToLeaveOut $SitesToLeaveOut) {
                    continue
                }

                $GraphSite = $null
                if (-not [string]::IsNullOrWhiteSpace($RowSiteId)) {
                    $GraphSite = $GraphBySiteId[$RowSiteId.ToLowerInvariant()]
                }
                if (-not $GraphSite -and -not [string]::IsNullOrWhiteSpace($RowUrl)) {
                    $GraphSite = $GraphByWebUrl[$RowUrl.TrimEnd('/').ToLowerInvariant()]
                }

                $RootWebTemplate = [string]$Row.TemplateName
                $StorageRaw = if ($null -ne $Row.'StorageUsed.') { $Row.'StorageUsed.' } else { $Row.StorageUsed }
                $FilesRaw = if ($null -ne $Row.'NumOfFiles.') { $Row.'NumOfFiles.' } else { $Row.NumOfFiles }

                $Results.Add([PSCustomObject]@{
                        type               = 'site'
                        id                 = $(if ($GraphSite.id) { $GraphSite.id } else { $RowSiteId })
                        siteId             = $(if ($GraphSite.sharepointIds.siteId) { $GraphSite.sharepointIds.siteId } else { $RowSiteId })
                        webId              = $GraphSite.sharepointIds.webId
                        displayName        = $(if ($RowTitle) { $RowTitle } else { $GraphSite.displayName })
                        name               = $(if ($GraphSite.name) { $GraphSite.name } else { $NameLeaf })
                        description        = $GraphSite.description
                        webUrl             = $(if ($RowUrl) { $RowUrl } else { $GraphSite.webUrl })
                        createdDateTime    = $(if ($Row.TimeCreated) { $Row.TimeCreated } else { $GraphSite.createdDateTime })
                        storageUsedInBytes = ConvertTo-StorageUsedBytes -Raw $StorageRaw
                        siteType           = ConvertTo-SiteTypeLabel -Template $RootWebTemplate -ItemType 'site'
                        rootWebTemplate    = $RootWebTemplate
                        fileCount          = ConvertTo-NullableInt64 -Raw $FilesRaw
                    })
            }

        } else {
            # Library drill-in.
            if (-not [string]::IsNullOrWhiteSpace($SiteId)) {
                $SiteSegment = $SiteId
            } else {
                $ParsedUrl = [System.Uri]$SiteUrl
                $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                    $ParsedUrl.Host
                } else {
                    "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
                }
            }

            $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id,webUrl,displayName,isPersonalSite" -tenantid $TenantFilter -asapp $true
            if ($SiteMeta.isPersonalSite -eq $true) {
                throw 'OneDrive sites are not supported in the SharePoint site browser.'
            }
            if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
                $SiteUrl = $SiteMeta.webUrl
            }
            if ([string]::IsNullOrWhiteSpace($SiteId)) {
                $SiteId = $SiteMeta.id
            }
            $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"
            $SiteInfo = [PSCustomObject]@{
                id          = $SiteId
                webUrl      = $SiteUrl
                displayName = $SiteMeta.displayName
                type        = 'site'
            }

            $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteSegment/lists?`$select=id,displayName,name,webUrl,list,createdDateTime" -tenantid $TenantFilter -asapp $true
            $Results = [System.Collections.Generic.List[object]]::new()
            foreach ($List in @($Lists | Where-Object { $_.list.hidden -ne $true -and $_.list.template -in @('documentLibrary', 'webPageLibrary') })) {
                $StorageUsed = $null
                $FileCount = $null
                $FileStreamSize = $null
                $MetadataSize = $null
                $VersionEstimate = $null
                try {
                    $Metrics = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$($List.id)')/RootFolder?`$select=StorageMetrics&`$expand=StorageMetrics" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                    $TotalSize = ConvertTo-StorageUsedBytes -Raw $Metrics.StorageMetrics.TotalSize
                    $FileStreamSize = ConvertTo-StorageUsedBytes -Raw $Metrics.StorageMetrics.TotalFileStreamSize
                    $MetadataSize = ConvertTo-StorageUsedBytes -Raw $Metrics.StorageMetrics.MetadataSize
                    $FileCount = ConvertTo-NullableInt64 -Raw $Metrics.StorageMetrics.TotalFileCount
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

                $Results.Add([PSCustomObject]@{
                        type                   = 'library'
                        id                     = $List.id
                        siteId                 = $SiteId
                        displayName            = $List.displayName
                        name                   = $List.name
                        template               = $List.list.template
                        siteType               = ConvertTo-SiteTypeLabel -ItemType 'library' -LibraryTemplate $List.list.template
                        webUrl                 = $List.webUrl
                        createdDateTime        = $List.createdDateTime
                        storageUsedInBytes     = $StorageUsed
                        fileStreamSizeInBytes  = $FileStreamSize
                        metadataSizeInBytes    = $MetadataSize
                        versionEstimateBytes   = $VersionEstimate
                        fileCount              = $FileCount
                    })
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list SharePoint browser items: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $StorageStatus = $null
    }

    $Body = @{'Results' = $Results }
    if ($SiteInfo) {
        $Body['Site'] = $SiteInfo
    }
    if ($StorageStatus) {
        $Body['StorageStatus'] = $StorageStatus
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
