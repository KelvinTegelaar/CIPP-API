function Invoke-ListCSPLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Result = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = 'Unable to retrieve CSP licenses, ensure that you have enabled the Sherweb integration and mapped the tenant in the integration settings.'
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Result)
    }

}
