using namespace System.Net

Function invoke-ListEmptyResults {
    <#
    .SYNOPSIS
     - Purposely lists an empty result
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
