function Set-CIPPDBCacheSites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId,
        [ValidateSet('SharePointSiteUsage', 'OneDriveUsageAccount', 'All', 'None')]
        [string[]]$Types = @('All')
    )

    try {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        $TenantId = $Tenant.customerId

        $TypesToCache = if (-not $Types -or $Types -contains 'None' -or $Types -contains 'All') {
            @('SharePointSiteUsage', 'OneDriveUsageAccount')
        } else {
            @($Types | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        foreach ($Type in $TypesToCache) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Caching sites report: $Type" -sev Debug

            if ($Type -eq 'SharePointSiteUsage') {
                $Filter = 'isPersonalSite eq false'
            } else {
                $Filter = 'isPersonalSite eq true'
            }

            $BulkRequests = @(
                @{
                    id     = 'listAllSites'
                    method = 'GET'
                    url    = "sites/getAllSites?`$filter=$($Filter)&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
                }
                @{
                    id     = 'usage'
                    method = 'GET'
                    url    = "reports/get$($Type)Detail(period='D7')?`$format=application/json&`$top=999"
                }
            )

            $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
            $Sites = ($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value
            $UsageBase64 = ($Result | Where-Object { $_.id -eq 'usage' }).body
            $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBase64))
            $Usage = ($UsageJson | ConvertFrom-Json).value

            $GraphRequest = foreach ($Site in $Sites) {
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

            if ($Type -eq 'SharePointSiteUsage') {
                $Int = 0
                $Requests = foreach ($Site in $GraphRequest) {
                    @{
                        id     = $Int++
                        method = 'GET'
                        url    = "sites/$($Site.siteId)/lists?`$select=id,name,list,parentReference"
                    }
                }

                try {
                    $DocumentLibraries = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' }
                    $GraphRequest = foreach ($Site in $GraphRequest) {
                        $ListId = ($DocumentLibraries | Where-Object { $_.parentReference.siteId -like "*$($Site.siteId)*" }).id
                        $Site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.webId)}&siteid={$($Site.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
                        $Site
                    }
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Error getting auto map urls: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
                }
            }

            $DbType = "Sites$Type"
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($GraphRequest)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($GraphRequest) -Count
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache sites report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
