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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @()
        })

}
