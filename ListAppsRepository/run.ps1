using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Search = $Request.Query.Search
$Repository = $Request.Query.Repository
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
                    Name        = $RepoPackage.title.'#text'
                    Author      = $RepoPackage.author.Name
                    Title       = $RepoPackage.properties.Title
                    Version     = $RepoPackage.properties.Version
                    Description = $RepoPackage.summary.'#text'
                    Created     = Get-Date -Date $RepoPackage.properties.Created.'#text' -Format 'MM/dd/yyyy HH:mm:ss'
                }  
            }
        }
        else {
            $IsError = $true
            $Message = 'No results found'
        }
    }
    else {
        $IsError = $true
        $Message = 'No search terms specified'
    }
}
catch {
    $IsError = $true
    $Message = "Repository error: $($_.Exception.Message)"
}

$PackageSearch = @{
    Search     = $Search
    Repository = $Repository
    Results    = @($Packages)
    Message    = $Message
    IsError    = $IsError
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $PackageSearch
    })
