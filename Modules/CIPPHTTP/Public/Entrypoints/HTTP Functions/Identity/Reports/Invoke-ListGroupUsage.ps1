function Invoke-ListGroupUsage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.Read
    .DESCRIPTION
        Compiles where each Entra group is used (Conditional Access, Intune assignments, group-based
        licensing, Teams, nested groups, Entra roles, enterprise applications, Exchange transport
        rules) from the CIPP reporting database cache. Always served from cache — no live Graph calls.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    try {
        # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
        if ($Request.Query.manualPagination -eq $true) {
            # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
            $PageSize = $Request.Query.PageSize -as [int]
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                    Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'Groups' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPGroupUsageReport -TenantFilter $Tenant -ErrorAction Stop }
                })
        }
        $GraphRequest = Get-CIPPGroupUsageReport -TenantFilter $TenantFilter -ErrorAction Stop
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $_.Exception.Message
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
