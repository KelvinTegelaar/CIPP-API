
Function Invoke-ListDomainAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DomainAnalyser.Read
    .DESCRIPTION
        Lists domain analysis results (SPF, DKIM, DMARC, DNSSEC) for tenant domains.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    $Results = Get-CIPPDomainAnalyser -TenantFilter $TenantFilter

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}
