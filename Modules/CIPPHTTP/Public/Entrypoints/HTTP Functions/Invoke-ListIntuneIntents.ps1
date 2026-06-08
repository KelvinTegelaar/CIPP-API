Function Invoke-ListIntuneIntents {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists Intune security baseline and endpoint protection intents (legacy template-based policies) with their settings and categories.
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
