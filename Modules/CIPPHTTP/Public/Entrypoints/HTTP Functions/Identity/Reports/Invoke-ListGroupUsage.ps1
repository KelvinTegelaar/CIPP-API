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
