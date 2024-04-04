using namespace System.Net

Function Invoke-ListSites {
    <#
    .FUNCTIONALITY
    Entrypoint
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
        $GraphRequest = $ParsedRequest | Select-Object @{ Name = 'UPN'; Expression = { $_.'Owner Principal Name' } },
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
        $URLs = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/sites/getAllSites?$select=SharePointIds' -asapp $true -tenantid $TenantFilter).SharePointIds

        $GraphRequest = foreach ($site in $GraphRequest) {
            $site.URL = ($URLs | Where-Object { $_.siteId -eq $site.SiteId }).siteUrl
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
            Body       = @($GraphRequest)
        })

}
