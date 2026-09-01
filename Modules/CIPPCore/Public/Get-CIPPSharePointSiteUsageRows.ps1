function Get-CIPPSharePointSiteUsageRows {
    <#
    .SYNOPSIS
        Builds SharePoint site listing and usage rows from SPO admin RLD plus Graph enrichment.

    .DESCRIPTION
        Active sites and usage metrics come from SPO admin RenderAdminListData. Graph getAllSites
        supplies webId and composite ids; an optional Get-CIPPSPOSite pass adds file-level archive
        fields; a Graph lists bulk pass fills AutoMapUrl. Used by the site usage cache collector
        and the live Invoke-ListSites SharePoint path.

    .PARAMETER TenantFilter
        Tenant to query.

    .PARAMETER IncludeArchive
        When set, merges ArchivedFileDiskUsed and AllowFileArchive from Get-CIPPSPOSite.

    .PARAMETER LogApi
        API name passed to Write-LogMessage for warnings and errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [switch]$IncludeArchive,

        [string]$LogApi = 'SharePointSiteUsage'
    )

    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    $TenantId = $Tenant.customerId
    $ReportRefreshDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $AdminRows = @(Get-CIPPSPOAdminListData -TenantFilter $TenantFilter -AdminUrl $SharePointInfo.AdminUrl -Type SharePoint)

    $GraphBulk = New-GraphBulkRequest -tenantid $TenantFilter -Requests @(
        @{
            id     = 'listAllSites'
            method = 'GET'
            url    = "sites/getAllSites?`$filter=isPersonalSite eq false&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
        }
    ) -asapp $true
    $SitesResponse = @($GraphBulk | Where-Object { $_.id -eq 'listAllSites' }) | Select-Object -First 1
    if ($null -eq $SitesResponse) {
        throw 'getAllSites response missing from Graph bulk batch'
    }
    if ($SitesResponse.status -and $SitesResponse.status -ne 200) {
        throw ($SitesResponse.body.error.message ?? "getAllSites failed with status $($SitesResponse.status)")
    }

    $GraphBySiteId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $GraphByWebUrl = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($GraphSite in @($SitesResponse.body.value)) {
        if ($null -eq $GraphSite) { continue }
        $Guid = [string]$GraphSite.sharepointIds.siteId
        if (-not [string]::IsNullOrWhiteSpace($Guid)) {
            $GraphBySiteId[$Guid.Trim('{}').ToLowerInvariant()] = $GraphSite
        }
        if (-not [string]::IsNullOrWhiteSpace($GraphSite.webUrl)) {
            $GraphByWebUrl[$GraphSite.webUrl.TrimEnd('/').ToLowerInvariant()] = $GraphSite
        }
    }

    $ArchiveByUrl = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($IncludeArchive) {
        try {
            foreach ($SpoSite in @(Get-CIPPSPOSite -TenantFilter $TenantFilter)) {
                if ([string]::IsNullOrWhiteSpace($SpoSite.Url)) { continue }
                $ArchiveByUrl[$SpoSite.Url.TrimEnd('/').ToLowerInvariant()] = @{
                    archivedFileDiskUsedBytes = $SpoSite.ArchivedFileDiskUsed
                    allowFileArchive          = $SpoSite.AllowFileArchive
                }
            }
        } catch {
            if ($_.Exception.Data['SPOAccessDenied']) {
                Write-LogMessage -API $LogApi -tenant $TenantFilter -message $_.Exception.Message -sev Warning
            } else {
                Write-LogMessage -API $LogApi -tenant $TenantFilter -message "SharePoint file archive enrichment skipped: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
            }
        }
    }

    $SiteListing = [System.Collections.Generic.List[object]]::new()
    $UsageRows = [System.Collections.Generic.List[object]]::new()

    foreach ($Row in $AdminRows) {
        if ($null -eq $Row) { continue }

        $RowUrl = [string]$Row.SiteUrl
        $RowTitle = [string]$Row.Title
        $RowSiteId = ([string]$Row.SiteId).Trim('{}')
        if ([string]::IsNullOrWhiteSpace($RowSiteId) -and [string]::IsNullOrWhiteSpace($RowUrl)) { continue }

        $GraphSite = $null
        if (-not [string]::IsNullOrWhiteSpace($RowSiteId)) {
            $GraphSite = $GraphBySiteId[$RowSiteId.ToLowerInvariant()]
        }
        if (-not $GraphSite -and $RowUrl) {
            $GraphSite = $GraphByWebUrl[$RowUrl.TrimEnd('/').ToLowerInvariant()]
        }

        $SiteGuid = if ($GraphSite -and $GraphSite.sharepointIds.siteId) { [string]$GraphSite.sharepointIds.siteId } else { $RowSiteId }
        $SiteGuid = $SiteGuid.Trim('{}')
        if ([string]::IsNullOrWhiteSpace($SiteGuid)) { continue }

        $OwnerEmail = [string]$Row.SiteOwnerEmail
        $OwnerName = [string]$Row.SiteOwnerName
        if ([string]::IsNullOrWhiteSpace($OwnerName)) { $OwnerName = $OwnerEmail }

        $ListingItem = [PSCustomObject]@{
            id              = $(if ($GraphSite -and $GraphSite.id) { $GraphSite.id } else { $SiteGuid })
            sharepointIds   = [PSCustomObject]@{
                siteId = $SiteGuid
                webId  = $(if ($GraphSite -and $GraphSite.sharepointIds.webId) { $GraphSite.sharepointIds.webId } else { $null })
            }
            createdDateTime = $(if ($Row.TimeCreated) { $Row.TimeCreated } elseif ($GraphSite) { $GraphSite.createdDateTime } else { $null })
            displayName     = $(if ($RowTitle) { $RowTitle } elseif ($GraphSite) { $GraphSite.displayName } else { $SiteGuid })
            webUrl          = $(if ($RowUrl) { $RowUrl } elseif ($GraphSite) { $GraphSite.webUrl } else { $null })
            isPersonalSite  = $false
            AutoMapUrl      = ''
        }

        if ($IncludeArchive -and -not [string]::IsNullOrWhiteSpace($ListingItem.webUrl)) {
            $ArchiveFields = $null
            if ($ArchiveByUrl.TryGetValue($ListingItem.webUrl.TrimEnd('/').ToLowerInvariant(), [ref]$ArchiveFields)) {
                $ListingItem | Add-Member -NotePropertyName 'archivedFileDiskUsedBytes' -NotePropertyValue $ArchiveFields.archivedFileDiskUsedBytes -Force
                $ListingItem | Add-Member -NotePropertyName 'allowFileArchive' -NotePropertyValue $ArchiveFields.allowFileArchive -Force
            }
        }

        [void]$SiteListing.Add($ListingItem)

        $UsageRows.Add([PSCustomObject]@{
                id                      = $SiteGuid
                siteId                  = $SiteGuid
                ownerDisplayName        = $OwnerName
                ownerPrincipalName      = $OwnerEmail
                lastActivityDate        = $Row.LastActivityOn
                fileCount               = $Row.NumOfFiles
                storageUsedInBytes      = $Row.StorageUsed
                storageAllocatedInBytes = $Row.StorageQuotaBytes
                rootWebTemplate         = ConvertTo-SPOUsageRootWebTemplate -TemplateName ([string]$Row.TemplateName)
                reportRefreshDate       = $ReportRefreshDate
            })
    }

    $RequestId = 0
    $ListRequests = foreach ($Site in $SiteListing) {
        if (-not $Site.sharepointIds.siteId) { continue }
        @{
            id     = $RequestId++
            method = 'GET'
            url    = "sites/$($Site.sharepointIds.siteId)/lists?`$select=id,name,list,parentReference"
        }
    }

    $ListIdBySiteKey = @{}
    if (@($ListRequests).Count -gt 0) {
        try {
            $LibraryLists = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($ListRequests) -asapp $true).body.value
            foreach ($List in @($LibraryLists)) {
                if ($List.list.template -ne 'DocumentLibrary') { continue }
                $ParentSiteId = $List.parentReference.siteId
                if (-not $ParentSiteId) { continue }
                foreach ($Key in ([string]$ParentSiteId -split ',')) {
                    if ($Key -and -not $ListIdBySiteKey.ContainsKey($Key)) { $ListIdBySiteKey[$Key] = $List.id }
                }
            }
            $LibraryLists = $null
        } catch {
            Write-LogMessage -Message "Error getting auto map urls for SharePoint site usage: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API $LogApi -LogData (Get-CippException -Exception $_)
        }
    }

    foreach ($Site in $SiteListing) {
        $SiteKey = [string]$Site.sharepointIds.siteId
        $ListId = if ($SiteKey) { $ListIdBySiteKey[$SiteKey] } else { $null }
        $Site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.sharepointIds.webId)}&siteid={$($Site.sharepointIds.siteId)}&webUrl=$($Site.webUrl)&listId={$ListId}"
    }

    return [PSCustomObject]@{
        SiteListing = $SiteListing
        UsageRows   = $UsageRows
    }
}
