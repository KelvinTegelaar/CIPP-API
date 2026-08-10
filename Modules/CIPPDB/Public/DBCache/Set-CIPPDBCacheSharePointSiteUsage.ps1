function Set-CIPPDBCacheSharePointSiteUsage {
    <#
    .SYNOPSIS
        Caches SharePoint site listing and site usage details for a tenant

    .PARAMETER TenantFilter
        The tenant to cache SharePoint site usage for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint site listing and usage' -sev Debug

        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        $TenantId = $Tenant.customerId

        $BulkRequests = @(
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$filter=isPersonalSite eq false&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
            }
            @{
                id     = 'usage'
                method = 'GET'
                url    = "reports/getSharePointSiteUsageDetail(period='D7')?`$format=application/json&`$top=999"
            }
        )

        $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
        $Sites = @(($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value)
        $UsageResponse = $Result | Where-Object { $_.id -eq 'usage' }
        if ($UsageResponse.status -and $UsageResponse.status -ne 200) {
            throw ($UsageResponse.body.error.message ?? "Usage report request failed with status $($UsageResponse.status)")
        }
        $UsageBody = $UsageResponse.body
        if ($UsageBody -is [string]) {
            $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBody))
            $UsageRows = @(($UsageJson | ConvertFrom-Json).value)
        } else {
            $UsageRows = @($UsageBody.value)
        }

        # Ensure a stable row key for usage rows.
        foreach ($UsageRow in $UsageRows) {
            if ($null -eq $UsageRow) { continue }
            $UsageRow | Add-Member -NotePropertyName 'id' -NotePropertyValue $UsageRow.siteId -Force
        }

        $SiteListing = [System.Collections.Generic.List[object]]::new()
        foreach ($Site in $Sites) {
            $SiteListing.Add([PSCustomObject]@{
                    id              = $Site.id
                    sharepointIds   = $Site.sharepointIds
                    createdDateTime = $Site.createdDateTime
                    displayName     = $Site.displayName
                    webUrl          = $Site.webUrl
                    isPersonalSite  = $Site.isPersonalSite
                    AutoMapUrl      = ''
                })
        }

        $RequestId = 0
        $ListRequests = foreach ($Site in $SiteListing) {
            @{
                id     = $RequestId++
                method = 'GET'
                url    = "sites/$($Site.sharepointIds.siteId)/lists?`$select=id,name,list,parentReference"
            }
        }

        # Reduce the library responses to one list id per site key as they are read, rather than
        # holding every document library object for the whole tenant. The previous version kept
        # them all and rescanned the array for each site, which is O(sites x libraries).
        # parentReference.siteId is a composite ('hostname,siteCollectionId,webId'), so each
        # comma-separated component is indexed - that is what the old '-like "*$siteId*"' test
        # matched, since a site GUID can only occur as a whole component. First writer wins,
        # matching the previous 'Select-Object -First 1'.
        $ListIdBySiteKey = @{}
        # A site with no sharepointIds.siteId produced the wildcard pattern '**' in the old
        # filter, which matches every library, so the first one won. Kept so those rows are
        # unchanged.
        $FirstLibraryListId = $null
        if ($ListRequests.Count -gt 0) {
            try {
                $LibraryLists = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($ListRequests) -asapp $true).body.value
                foreach ($List in $LibraryLists) {
                    if ($List.list.template -ne 'DocumentLibrary') { continue }
                    if ($null -eq $FirstLibraryListId) { $FirstLibraryListId = $List.id }
                    $ParentSiteId = $List.parentReference.siteId
                    if (-not $ParentSiteId) { continue }
                    foreach ($Key in ([string]$ParentSiteId -split ',')) {
                        if ($Key -and -not $ListIdBySiteKey.ContainsKey($Key)) { $ListIdBySiteKey[$Key] = $List.id }
                    }
                }
                $LibraryLists = $null
            } catch {
                Write-LogMessage -Message "Error getting auto map urls for SharePoint cache: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'CIPPDBCache' -LogData (Get-CippException -Exception $_)
            }
        }
        $ListRequests = $null

        foreach ($Site in $SiteListing) {
            $SiteKey = [string]$Site.sharepointIds.siteId
            $ListId = if ($SiteKey) { $ListIdBySiteKey[$SiteKey] } else { $FirstLibraryListId }
            $Site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.sharepointIds.webId)}&siteid={$($Site.sharepointIds.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
        }
        $ListIdBySiteKey = $null

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' -Data @($SiteListing) -AddCount

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' -Data @($UsageRows) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint site listing and usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint site usage: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
