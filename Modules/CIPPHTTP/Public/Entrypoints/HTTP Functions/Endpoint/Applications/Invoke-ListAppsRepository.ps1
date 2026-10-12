Function Invoke-ListAppsRepository {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.Read
    .DESCRIPTION
        Searches external application repositories (WinGet, Chocolatey, etc.) for available application packages.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Search = $Request.Body.Search
    $Repository = $Request.Body.Repository
    $Packages = @()
    $Message = ''
    $IsError = $false
    $StatusCode = [HttpStatusCode]::OK

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
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    } catch {
        $IsError = $true
        $Message = "Repository error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $PackageSearch = @{
        Search  = $Search
        Results = @($Packages | Sort-Object -Property packagename)
        Message = $Message
        IsError = $IsError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $PackageSearch
        })

}
