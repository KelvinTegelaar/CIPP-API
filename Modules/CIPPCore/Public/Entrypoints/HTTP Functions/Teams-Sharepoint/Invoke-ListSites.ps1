using namespace System.Net

Function Invoke-ListSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    $Type = $request.query.Type
    $UserUPN = $request.query.UserUPN

    if (!$TenantFilter) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
        return
    }

    if (!$Type) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Type is required'
            })
        return
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
                Write-LogMessage -Message "Error getting auto map urls: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'ListSites' -LogData (Get-CippException -Exception $_)
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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object -Property displayName)
        })

}
