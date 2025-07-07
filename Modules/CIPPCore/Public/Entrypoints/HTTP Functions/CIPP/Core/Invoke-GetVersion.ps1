using namespace System.Net

function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $CIPPVersion = $request.query.LocalVersion

    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Version
    }

}
