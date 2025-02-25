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


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
