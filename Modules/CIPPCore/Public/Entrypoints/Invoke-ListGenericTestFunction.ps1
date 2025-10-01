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


    $graphRequest = ($Headers.'x-ms-original-url').split('/api') | Select-Object -First 1

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($graphRequest)
    }

}
