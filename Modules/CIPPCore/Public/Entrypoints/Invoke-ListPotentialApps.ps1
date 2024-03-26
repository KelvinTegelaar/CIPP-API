using namespace System.Net

Function Invoke-ListPotentialApps {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($request.body.type -eq 'WinGet') {
        $body = @"
{"MaximumResults":50,"Filters":[{"PackageMatchField":"Market","RequestMatch":{"KeyWord":"US","MatchType":"CaseInsensitive"}}],"Query":{"KeyWord":"$($Request.Body.SearchString)","MatchType":"Substring"}}
"@
        $DataRequest = (Invoke-RestMethod -Uri 'https://storeedgefd.dsx.mp.microsoft.com/v9.0/manifestSearch' -Method POST -Body $body -ContentType 'Application/json').data | Select-Object @{l = 'applicationName'; e = { $_.packagename } }, @{l = 'packagename'; e = { $_.packageIdentifier } } | Sort-Object -Property applicationName
    }

    if ($Request.body.type -eq 'Choco') {
        $DataRequest = Invoke-RestMethod -Uri "https://community.chocolatey.org/api/v2/Search()?`$filter=IsLatestVersion&`$skip=0&`$top=999&searchTerm=%27$($request.body.SearchString)%27&targetFramework=%27%27&includePrerelease=false" -ContentType 'application/json' | Select-Object @{l = 'applicationName'; e = { $_.properties.Title } }, @{l = 'packagename'; e = { $_.title.'#text' } } | Sort-Object -Property applicationName
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($DataRequest)
        })

}
