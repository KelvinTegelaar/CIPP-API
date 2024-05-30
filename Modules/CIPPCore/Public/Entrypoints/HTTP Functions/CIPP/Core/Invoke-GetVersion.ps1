using namespace System.Net

Function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $APIVersion = (Get-Content 'version_latest.txt' -Raw).trim()
    $CIPPVersion = $request.query.localversion

    $RemoteAPIVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt').trim()
    $RemoteCIPPVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP/master/public/version_latest.txt').trim()

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

}
