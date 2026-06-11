using namespace System.Net

function invoke-ListEmptyResults {
    <#
    .SYNOPSIS
     - Purposely lists an empty result
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Returns an empty results array. Used as a placeholder endpoint.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
