function Invoke-ListShadowAI {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Compiles a Shadow AI overview for a tenant by matching CACHED data from the CIPP reporting
        database (DetectedApps, ServicePrincipals, OAuth2PermissionGrants) against the curated AI
        catalog (Config/ShadowAI.json). No live Graph enumeration is performed - refresh the data by
        syncing those caches (ExecCIPPDBCache). The only live call is a bounded, best-effort 7-day
        sign-in lookup for the matched AI applications.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Body = Get-CIPPShadowAIReport -TenantFilter $TenantFilter

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
