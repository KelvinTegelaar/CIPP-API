Function Invoke-ListIPWhitelist {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.IPDatabase.Read
    .DESCRIPTION
        Lists trusted IP addresses configured in CIPP for IP-based access control.
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
