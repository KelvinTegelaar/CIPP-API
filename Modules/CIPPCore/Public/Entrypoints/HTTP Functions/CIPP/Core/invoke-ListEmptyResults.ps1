using namespace System.Net

function invoke-ListEmptyResults {
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

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @()
    }

}
