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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $type = $request.query.Type
    $UserUPN = $request.query.UserUPN
    try {
        $Result = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D7')" -tenantid $TenantFilter | ConvertFrom-Csv

        if ($UserUPN) {
            $ParsedRequest = $Result | Where-Object { $_.'Owner Principal Name' -eq $UserUPN }
        } else {
            $ParsedRequest = $Result
        }
        $GraphRequest = $ParsedRequest | Select-Object AutoMapUrl, @{ Name = 'UPN'; Expression = { $_.'Owner Principal Name' } },
        @{ Name = 'displayName'; Expression = { $_.'Owner Display Name' } },
        @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
        @{ Name = 'FileCount'; Expression = { [int]$_.'File Count' } },
        @{ Name = 'UsedGB'; Expression = { [math]::round($_.'Storage Used (Byte)' / 1GB, 2) } },
        @{ Name = 'URL'; Expression = { $_.'Site URL' } },
        @{ Name = 'Allocated'; Expression = { [math]::round($_.'Storage Allocated (Byte)' / 1GB, 2) } },
        @{ Name = 'Template'; Expression = { $_.'Root Web Template' } },
        @{ Name = 'siteid'; Expression = { $_.'site Id' } }

        #Temporary workaround for url as report is broken.
        #This API is so stupid its great.
        $URLs = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/getAllSites?$select=SharePointIds,name,webUrl,displayName,siteCollection' -asapp $true -tenantid $TenantFilter
        $int = 0
        if ($Type -eq 'SharePointSiteUsage') {
            $Requests = foreach ($url in $URLs) {
                @{
                    id     = $int++
                    method = 'GET'
                    url    = "sites/$($url.sharepointIds.siteId)/lists?`$select=id,name,list,parentReference"
                }
            }
            $Requests = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' }
        }
        $GraphRequest = foreach ($site in $GraphRequest) {
            $SiteURLs = ($URLs.SharePointIds | Where-Object { $_.siteId -eq $site.SiteId })
            $site.URL = $SiteURLs.siteUrl
            $ListId = ($Requests | Where-Object { $_.parentReference.siteId -like "*$($SiteURLs.siteId)*" }).id
            $site.AutoMapUrl = "tenantId=$($SiteUrls.tenantId)&webId={$($SiteUrls.webId)}&siteid={$($SiteURLs.siteId)}&webUrl=$($SiteURLs.siteUrl)&listId={$($ListId)}"
            $site
        }

        $StatusCode = [HttpStatusCode]::OK
    
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    if ($Request.query.URLOnly -eq 'true') {
        $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.URL }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object -Property UPN)
        })

}
