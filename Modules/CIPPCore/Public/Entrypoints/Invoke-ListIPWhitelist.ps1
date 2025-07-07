using namespace System.Net

function Invoke-ListIPWhitelist {
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

    $Table = Get-CippTable -tablename 'trustedIps'
    $body = Get-CIPPAzDataTableEntity @Table

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($body)
    }
}
