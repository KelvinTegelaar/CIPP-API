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

    $Table = Get-CippTable -tablename 'trustedIps'
    $body = Get-CIPPAzDataTableEntity @Table

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        })
}