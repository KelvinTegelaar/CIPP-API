function Invoke-ExecBreachSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Queues a breach search for a tenant against Have I Been Pwned. The search runs as a background job and can take up to 24 hours; this returns as soon as it is queued, not with the results. Read the results with ListBreachesTenant.
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
