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
            $SafeSearch = [uri]::EscapeDataString($Search.Replace("'", "''"))
            $Url = "$Repository/Search()?`$filter=IsLatestVersion&`$skip=0&`$top=30&searchTerm='$SafeSearch'&targetFramework=''&includePrerelease=false"

            # The repository URL is caller-supplied, so every hop (redirects included) must be a public http(s) host.
            $Response = $null
            for ($Hop = 0; $Hop -lt 5 -and -not $Response; $Hop++) {
                $Target = [uri]$Url
                if (-not $Target.IsAbsoluteUri -or $Target.Scheme -notin 'http', 'https') { throw [System.ArgumentException]::new('The repository must be an http or https URL.') }
                foreach ($Address in [System.Net.Dns]::GetHostAddresses($Target.DnsSafeHost)) {
                    $A = if ($Address.IsIPv4MappedToIPv6) { $Address.MapToIPv4() } else { $Address }
                    $B = $A.GetAddressBytes()
                    if ([System.Net.IPAddress]::IsLoopback($A) -or $A.IsIPv6LinkLocal -or $A.IsIPv6SiteLocal -or $A.IsIPv6UniqueLocal -or
                        ($B.Count -eq 4 -and ($B[0] -in 0, 10, 127 -or ($B[0] -eq 169 -and $B[1] -eq 254) -or ($B[0] -eq 172 -and $B[1] -ge 16 -and $B[1] -le 31) -or ($B[0] -eq 192 -and $B[1] -eq 168) -or ($B[0] -eq 100 -and $B[1] -ge 64 -and $B[1] -le 127)))) {
                        throw [System.ArgumentException]::new("The repository host $($Target.Host) is a private or local address.")
                    }
                }
                try {
                    $Response = Invoke-WebRequest $Url -MaximumRedirection 0 -ErrorAction Stop
                } catch {
                    $Location = $_.Exception.Response.Headers.Location
                    if (-not $Location) { throw }
                    $Url = [uri]::new($Target, $Location).AbsoluteUri
                }
            }
            if (-not $Response) { throw 'The repository redirected too many times.' }
            $RepoPackages = ([xml]$Response.Content).feed.entry

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
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
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
