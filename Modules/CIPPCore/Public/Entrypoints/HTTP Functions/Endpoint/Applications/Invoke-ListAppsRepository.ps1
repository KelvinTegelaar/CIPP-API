using namespace System.Net

Function Invoke-ListAppsRepository {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Search = $Request.Body.Search
    $Repository = $Request.Body.Repository
    $Packages = @()
    $Message = ''
    $IsError = $false

    try {
        if (!([string]::IsNullOrEmpty($Search))) {
            if ([string]::IsNullOrEmpty($Repository)) {
                $Repository = 'https://chocolatey.org/api/v2'
            }

            # Latest version, top 30 results matching search term
            $SearchPath = "Search()?`$filter=IsLatestVersion&`$skip=0&`$top=30&searchTerm='$Search'&targetFramework=''&includePrerelease=false"

            $Url = "$Repository/$SearchPath"
            $RepoPackages = Invoke-RestMethod $Url -ErrorAction Stop

            if (($RepoPackages | Measure-Object).Count -gt 0) {
                $Packages = foreach ($RepoPackage in $RepoPackages) {
                    [PSCustomObject]@{
                        packagename     = $RepoPackage.title.'#text'
                        author          = $RepoPackage.author.Name
                        applicationName = $RepoPackage.properties.Title
                        version         = $RepoPackage.properties.Version
                        description     = $RepoPackage.summary.'#text'
                        customRepo      = $Repository
                        created         = Get-Date -Date $RepoPackage.properties.Created.'#text' -Format 'MM/dd/yyyy HH:mm:ss'
                    }
                }
            } else {
                $IsError = $true
                $Message = 'No results found'
            }
        } else {
            $IsError = $true
            $Message = 'No search terms specified'
        }
    } catch {
        $IsError = $true
        $Message = "Repository error: $($_.Exception.Message)"
    }

    $PackageSearch = @{
        Search  = $Search
        Results = @($Packages | Sort-Object -Property packagename)
        Message = $Message
        IsError = $IsError
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $PackageSearch
        })

}
