using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$APIVersion = Get-Content "version_latest.txt" | Out-String
$CIPPVersion = $request.query.localversion

$RemoteAPIVersion = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt"
$RemoteCIPPVersion = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/KelvinTegelaar/CIPP/master/version_latest.txt"

$version = [PSCustomObject]@{
    LocalCIPPVersion     = $CIPPVersion
    RemoteCIPPVersion    = $RemoteCIPPVersion
    LocalCIPPAPIVersion  = $APIVersion
    RemoteCIPPAPIVersion = $RemoteAPIVersion
    OutOfDateCIPP        = ([version]$RemoteCIPPVersion -gt [version]$CIPPVersion)
    OutOfDateCIPPAPI     = ([version]$RemoteAPIVersion -gt [version]$APIVersion)
}
# Write to the Azure Functions log stream.

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Version
    })