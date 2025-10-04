using namespace System.Net

Function Invoke-ListIPWhitelist {
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


    $Table = Get-CippTable -tablename 'trustedIps'
    $body = Get-CIPPAzDataTableEntity @Table

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        }
}
