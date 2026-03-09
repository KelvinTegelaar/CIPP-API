using namespace System.Net

function invoke-ListEmptyResults {
    <#
    .SYNOPSIS
     - Purposely lists an empty result
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
