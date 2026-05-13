function Invoke-ListSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $TenantFilter = $Request.Query.TenantFilter
    $Type = $Request.Query.Type
    $UseReportDB = $Request.Query.UseReportDB

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

    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB -eq 'true') {
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
            if ($Request.query.URLOnly -eq 'true') {
                $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.webUrl }
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest | Sort-Object -Property displayName)
                })
        }
    }

    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    $TenantId = $Tenant.customerId

    if ($Type -eq 'SharePointSiteUsage') {
        $Filter = 'isPersonalSite eq false'
    } else {
        $Filter = 'isPersonalSite eq true'
    }

    try {
        $BulkRequests = @(
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$filter=$($Filter)&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
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
                storageUsedInGigabytes      = [math]::round($SiteUsage.storageUsedInBytes / 1GB, 2)
                storageAllocatedInGigabytes = [math]::round($SiteUsage.storageAllocatedInBytes / 1GB, 2)
                storageUsedInBytes          = $SiteUsage.storageUsedInBytes
                storageAllocatedInBytes     = $SiteUsage.storageAllocatedInBytes
                rootWebTemplate             = $SiteUsage.rootWebTemplate
                reportRefreshDate           = $SiteUsage.reportRefreshDate
                AutoMapUrl                  = ''
            }
        }

        $int = 0
        if ($Type -eq 'SharePointSiteUsage') {
            $Requests = foreach ($Site in $GraphRequest) {
                @{
                    id     = $int++
                    method = 'GET'
                    url    = "sites/$($Site.siteId)/lists?`$select=id,name,list,parentReference"
                }
            }
            try {
                $Requests = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' }
            } catch {
                Write-LogMessage -Headers $Headers -Message "Error getting auto map urls: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'ListSites' -LogData (Get-CippException -Exception $_)
            }
            $GraphRequest = foreach ($Site in $GraphRequest) {
                $ListId = ($Requests | Where-Object { $_.parentReference.siteId -like "*$($Site.siteId)*" }).id
                $site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.webId)}&siteid={$($Site.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
                $site
            }
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    if ($Request.query.URLOnly -eq 'true') {
        $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.webUrl }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object -Property displayName)
        })

}
