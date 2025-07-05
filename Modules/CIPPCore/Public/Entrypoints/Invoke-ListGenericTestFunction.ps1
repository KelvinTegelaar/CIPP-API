using namespace System.Net

function Invoke-ListGenericTestFunction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $GraphRequest = ($Headers.'x-ms-original-url').split('/api') | Select-Object -First 1

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }
}
