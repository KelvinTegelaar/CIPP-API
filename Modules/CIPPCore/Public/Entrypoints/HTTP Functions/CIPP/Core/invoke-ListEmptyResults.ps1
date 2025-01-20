using namespace System.Net

Function invoke-ListEmptyResults {
    <#
    .FUNCTIONALITY
        Entrypoint - Purposely lists an empty result
    .ROLE
        CIPP.Core
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
