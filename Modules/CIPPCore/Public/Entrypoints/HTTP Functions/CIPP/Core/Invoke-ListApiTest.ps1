function Invoke-ListApiTest {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($Request | ConvertTo-Json -Depth 5)
        })
}
