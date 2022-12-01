using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

if ($request.body.type -eq "WinGet") {
    $body = @"
{"MaximumResults":50,"Filters":[{"PackageMatchField":"Market","RequestMatch":{"KeyWord":"US","MatchType":"CaseInsensitive"}}],"Query":{"KeyWord":"$($Request.Body.SearchString)","MatchType":"Substring"}}
"@
    $DataRequest = (Invoke-RestMethod -Uri "https://storeedgefd.dsx.mp.microsoft.com/v9.0/manifestSearch" -Method POST -Body $body -ContentType "Application/json").data | Select-Object *, @{l = 'label'; e = { $_.packageName } }, @{l = 'value'; e = { $_.packageIdentifier } }
}

if ($Request.body.type -eq "Choco") {
    $DataRequest = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/KelvinTegelaar/CIPP/master/version_latest.txt"
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($DataRequest)
    })