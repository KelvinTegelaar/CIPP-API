Function Invoke-ListIntuneIntents {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/Intents?`$expand=settings,categories" -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
