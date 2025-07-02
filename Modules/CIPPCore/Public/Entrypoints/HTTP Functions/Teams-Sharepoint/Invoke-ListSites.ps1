using namespace System.Net

function Invoke-ListSites {
    <#
    .SYNOPSIS
    List SharePoint sites with usage information
    
    .DESCRIPTION
    Retrieves SharePoint sites with detailed usage information including storage, file counts, and activity data using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Sites
    Description: Retrieves SharePoint sites with detailed usage information including storage, file counts, activity data, and auto-map URLs using Microsoft Graph API with bulk requests
    Tags: SharePoint,Sites,Usage,Storage,Graph API
    Parameter: TenantFilter (string) [query] - Target tenant identifier (required)
    Parameter: Type (string) [query] - Site type: SharePointSiteUsage or OneDriveSiteUsage (required)
    Parameter: UserUPN (string) [query] - User Principal Name for filtering
    Parameter: URLOnly (boolean) [query] - Whether to return only sites with URLs
    Response: Returns an array of site objects with the following properties:
    Response: - siteId (string): SharePoint site ID
    Response: - webId (string): SharePoint web ID
    Response: - createdDateTime (string): Site creation date and time
    Response: - displayName (string): Site display name
    Response: - webUrl (string): Site web URL
    Response: - ownerDisplayName (string): Site owner display name
    Response: - ownerPrincipalName (string): Site owner principal name
    Response: - lastActivityDate (string): Last activity date
    Response: - fileCount (number): Number of files in the site
    Response: - storageUsedInGigabytes (number): Storage used in GB
    Response: - storageAllocatedInGigabytes (number): Storage allocated in GB
    Response: - storageUsedInBytes (number): Storage used in bytes
    Response: - storageAllocatedInBytes (number): Storage allocated in bytes
    Response: - rootWebTemplate (string): Root web template
    Response: - reportRefreshDate (string): Report refresh date
    Response: - AutoMapUrl (string): Auto-map URL for SharePoint sites
    Response: On error: Error message with HTTP 403 status
    Response: On missing parameters: Error message with HTTP 400 status
    Example: [
      {
        "siteId": "12345678-1234-1234-1234-123456789012",
        "webId": "87654321-4321-4321-4321-210987654321",
        "createdDateTime": "2024-01-15T10:30:00Z",
        "displayName": "Project Site",
        "webUrl": "https://contoso.sharepoint.com/sites/project",
        "ownerDisplayName": "John Doe",
        "ownerPrincipalName": "john.doe@contoso.com",
        "lastActivityDate": "2024-01-20",
        "fileCount": 150,
        "storageUsedInGigabytes": 2.5,
        "storageAllocatedInGigabytes": 25.0,
        "storageUsedInBytes": 2684354560,
        "storageAllocatedInBytes": 26843545600,
        "rootWebTemplate": "Team Site",
        "reportRefreshDate": "2024-01-21",
        "AutoMapUrl": "tenantId=12345678-1234-1234-1234-123456789012&webId={87654321-4321-4321-4321-210987654321}&siteid={12345678-1234-1234-1234-123456789012}&webUrl=https://contoso.sharepoint.com/sites/project&listId={list-id}"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
    }
    else {
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
            }
            catch {
                Write-LogMessage -Headers $Headers -Message "Error getting auto map urls: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'ListSites' -LogData (Get-CippException -Exception $_)
            }
            $GraphRequest = foreach ($Site in $GraphRequest) {
                $ListId = ($Requests | Where-Object { $_.parentReference.siteId -like "*$($Site.siteId)*" }).id
                $site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.webId)}&siteid={$($Site.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
                $site
            }
        }
        $StatusCode = [HttpStatusCode]::OK

    }
    catch {
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
