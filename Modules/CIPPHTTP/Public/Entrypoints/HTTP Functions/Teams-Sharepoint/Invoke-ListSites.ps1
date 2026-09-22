function Invoke-ListSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists SharePoint sites or OneDrive usage for a tenant. Requires a Type parameter (SharePointSiteUsage or OneDriveUsageAccount). SharePoint live data uses SPO admin RLD plus Graph enrichment; OneDrive live data uses Graph usage reports. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $TenantFilter = $Request.Query.TenantFilter
    $Type = $Request.Query.Type
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    if (!$TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
    }

    if (!$Type) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Type is required'
            })
    }

    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
        try {
            if ($Type -eq 'SharePointSiteUsage') {
                $GraphRequest = Get-CIPPSharePointSiteUsageReport -TenantFilter $TenantFilter -ErrorAction Stop
            } elseif ($Type -eq 'OneDriveUsageAccount') {
                $GraphRequest = Get-CIPPOneDriveUsageReport -TenantFilter $TenantFilter -ErrorAction Stop
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
        }

        if ($null -ne $GraphRequest) {
            if ($Request.query.URLOnly -eq $true) {
                $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.webUrl }
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest | Sort-Object -Property displayName)
                })
        }
    }

    try {
        if ($Type -eq 'SharePointSiteUsage') {
            $Built = Get-CIPPSharePointSiteUsageRows -TenantFilter $TenantFilter -LogApi 'ListSites'
            $UsageBySiteId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($UsageRow in @($Built.UsageRows)) {
                if (-not [string]::IsNullOrWhiteSpace($UsageRow.siteId)) {
                    $UsageBySiteId[[string]$UsageRow.siteId.Trim('{}')] = $UsageRow
                }
            }

            $GraphRequest = foreach ($Site in @($Built.SiteListing)) {
                $SiteUsage = $null
                [void]$UsageBySiteId.TryGetValue([string]$Site.sharepointIds.siteId.Trim('{}'), [ref]$SiteUsage)
                ConvertTo-CIPPSharePointSiteUsagePayload -Site $Site -SiteUsage $SiteUsage
            }
        } else {
            $BulkRequests = @(
                @{
                    id     = 'listAllSites'
                    method = 'GET'
                    url    = "sites/getAllSites?`$filter=isPersonalSite eq true&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
                }
                @{
                    id     = 'usage'
                    method = 'GET'
                    url    = "reports/get$($type)Detail(period='D7')?`$format=application/json&`$top=999"
                }
            )

            $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
            $Sites = ($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value
            $UsageResponse = $Result | Where-Object { $_.id -eq 'usage' }
            if ($UsageResponse.status -and $UsageResponse.status -ne 200) {
                throw ($UsageResponse.body.error.message ?? "Usage report request failed with status $($UsageResponse.status)")
            }
            $UsageBody = $UsageResponse.body
            if ($UsageBody -is [string]) {
                $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBody))
                $Usage = ($UsageJson | ConvertFrom-Json).value
            } else {
                $Usage = @($UsageBody.value)
            }

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
                    storageUsedInGigabytes      = if ($null -ne $SiteUsage.storageUsedInBytes) { [math]::round([double]$SiteUsage.storageUsedInBytes / 1GB, 2) } else { $null }
                    storageAllocatedInGigabytes = if ($null -ne $SiteUsage.storageAllocatedInBytes) { [math]::round([double]$SiteUsage.storageAllocatedInBytes / 1GB, 2) } else { $null }
                    storageUsedInBytes          = $SiteUsage.storageUsedInBytes
                    storageAllocatedInBytes     = $SiteUsage.storageAllocatedInBytes
                    rootWebTemplate             = $SiteUsage.rootWebTemplate
                    reportRefreshDate           = $SiteUsage.reportRefreshDate
                    AutoMapUrl                  = ''
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    if ($Request.query.URLOnly -eq $true) {
        $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.webUrl }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object -Property displayName)
        })

}
