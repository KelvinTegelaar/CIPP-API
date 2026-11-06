Function Invoke-ListPotentialApps {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    .DESCRIPTION
        Searches application repositories (WinGet, Chocolatey) for available applications matching a search string.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    if ($request.body.type -eq 'WinGet') {
        # Store search indexes differ per market (US omits Spotify and iTunes); package IDs are global.
        $Searches = foreach ($Market in 'US', 'GB', 'AU', 'PM', 'LB') {
            $Search = [CIPP.CIPPConcurrentRequest]::new()
            $Search.Uri = 'https://storeedgefd.dsx.mp.microsoft.com/v9.0/manifestSearch'
            $Search.Method = 'POST'
            $Search.ContentType = 'application/json'
            $Search.Body = @{
                MaximumResults = 50
                Filters        = @(@{ PackageMatchField = 'Market'; RequestMatch = @{ KeyWord = $Market; MatchType = 'CaseInsensitive' } })
                Query          = @{ KeyWord = [string]$Request.Body.SearchString; MatchType = 'Substring' }
            } | ConvertTo-Json -Depth 5 -Compress
            $Search
        }
        $Responses = [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@($Searches), 5, 2)
        if (-not $Responses.Where({ $_.IsSuccess })) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Microsoft Store search failed: $($Responses[0].Error ?? "HTTP $($Responses[0].StatusCode)")" }
            }
        }
        $Apps = [System.Collections.Generic.Dictionary[string, object]]::new()
        foreach ($Sent in $Responses.Where({ $_.IsSuccess })) {
            foreach ($App in ([CIPP.CippJson]::ConvertFromResponse($Sent.Result)).Data) {
                if (-not $Apps.ContainsKey($App.PackageIdentifier)) {
                    $Apps[$App.PackageIdentifier] = [PSCustomObject]@{ applicationName = $App.PackageName; packagename = $App.PackageIdentifier }
                }
            }
        }
        $DataRequest = $Apps.Values | Sort-Object -Property applicationName
    }

    if ($Request.Body.type -eq 'Choco') {
        $DataRequest = Invoke-RestMethod -Uri "https://community.chocolatey.org/api/v2/Search()?`$filter=IsLatestVersion&`$skip=0&`$top=999&searchTerm=%27$($Request.Body.SearchString)%27&targetFramework=%27%27&includePrerelease=false" -ContentType 'application/json' | Select-Object @{l = 'applicationName'; e = { $_.properties.Title } }, @{l = 'packagename'; e = { $_.title.'#text' } } | Sort-Object -Property applicationName
    }


    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($DataRequest)
        }

}
