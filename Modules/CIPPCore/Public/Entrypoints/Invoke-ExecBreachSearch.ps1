function Invoke-ExecBreachSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.body.tenantFilter

    #Move to background job
    New-BreachTenantSearch -TenantFilter $TenantFilter
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = "Executing Search for $TenantFilter. This may take up to 24 hours to complete." }
        })

}
