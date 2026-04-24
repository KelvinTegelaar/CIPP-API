Function Invoke-ListIPWhitelist {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'trustedIps'
    $body = Get-CIPPAzDataTableEntity @Table

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        }
}
