function Push-ListSitesSharePointAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $TenantId = $Tenant.customerId
    $Table = Get-CIPPTable -TableName 'cacheSharePointSites'

    try {
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

        $Result = New-GraphBulkRequest -tenantid $DomainName -Requests @($BulkRequests) -asapp $true
        $Sites = ($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value
        $UsageBase64 = ($Result | Where-Object { $_.id -eq 'usage' }).body
        $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBase64))
        $Usage = ($UsageJson | ConvertFrom-Json).value

        $SiteData = foreach ($Site in $Sites) {
            $SiteUsage = $Usage | Where-Object { $_.siteId -eq $Site.sharepointIds.siteId }
            [PSCustomObject]@{
                siteId                      = $Site.sharepointIds.siteId
                webId                       = $Site.sharepointIds.webId
                createdDateTime             = $Site.createdDateTime
                displayName                 = $Site.displayName
                webUrl                      = $Site.webUrl
                ownerDisplayName            = $SiteUsage.ownerDisplayName
                ownerPrincipalName          = $SiteUsage.ownerPrincipalName
                lastActivityDate            = $SiteUsage.lastActivityDate
                fileCount                   = $SiteUsage.fileCount
                storageUsedInGigabytes      = [math]::round($SiteUsage.storageUsedInBytes / 1GB, 2)
                storageAllocatedInGigabytes = [math]::round($SiteUsage.storageAllocatedInBytes / 1GB, 2)
                storageUsedInBytes          = $SiteUsage.storageUsedInBytes
                storageAllocatedInBytes     = $SiteUsage.storageAllocatedInBytes
                rootWebTemplate             = $SiteUsage.rootWebTemplate
                reportRefreshDate           = $SiteUsage.reportRefreshDate
                AutoMapUrl                  = ''
            }
        }

        # Get AutoMapUrl for SharePoint sites
        $int = 0
        $Requests = foreach ($Site in $SiteData) {
            @{
                id     = $int++
                method = 'GET'
                url    = "sites/$($Site.siteId)/lists?`$select=id,name,list,parentReference"
            }
        }
        try {
            $ListResults = (New-GraphBulkRequest -tenantid $DomainName -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' }
        } catch {
            $ListResults = @()
        }

        foreach ($Site in $SiteData) {
            $ListId = ($ListResults | Where-Object { $_.parentReference.siteId -like "*$($Site.siteId)*" }).id
            $Site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.webId)}&siteid={$($Site.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"

            $GUID = (New-Guid).Guid
            $PolicyData = @{
                siteId                      = $Site.siteId
                webId                       = $Site.webId
                createdDateTime             = $Site.createdDateTime
                displayName                 = $Site.displayName
                webUrl                      = $Site.webUrl
                ownerDisplayName            = $Site.ownerDisplayName
                ownerPrincipalName          = $Site.ownerPrincipalName
                lastActivityDate            = $Site.lastActivityDate
                fileCount                   = $Site.fileCount
                storageUsedInGigabytes      = $Site.storageUsedInGigabytes
                storageAllocatedInGigabytes = $Site.storageAllocatedInGigabytes
                storageUsedInBytes          = $Site.storageUsedInBytes
                storageAllocatedInBytes     = $Site.storageAllocatedInBytes
                rootWebTemplate             = $Site.rootWebTemplate
                reportRefreshDate           = $Site.reportRefreshDate
                AutoMapUrl                  = $Site.AutoMapUrl
                Tenant                      = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'SharePointSite'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            displayName = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'SharePointSite'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
