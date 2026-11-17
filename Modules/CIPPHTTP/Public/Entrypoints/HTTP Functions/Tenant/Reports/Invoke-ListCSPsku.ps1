function Invoke-ListCSPsku {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists available CSP SKUs and current subscriptions for a tenant via the enabled CSP integration (Sherweb or External CSP).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $CurrentSkuOnly = $Request.Query.currentSkuOnly

    try {
        if ((Get-CIPPCSPProvider) -eq 'ExternalCSP') {
            $ExternalAction = if ($CurrentSkuOnly) { 'Subscriptions' } else { 'Catalog' }
            $GraphRequest = Invoke-ExternalCSPRequest -Action $ExternalAction -TenantFilter $TenantFilter
        } elseif ($CurrentSkuOnly) {
            $GraphRequest = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
        } else {
            $GraphRequest = Get-SherwebCatalog -TenantFilter $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        if ($_.Exception.Message -eq 'No Sherweb mapping found') {
            $GraphRequest = @()
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $GraphRequest = [PSCustomObject]@{
                name = @(@{value = 'Error getting catalog' })
                sku  = $_.Exception.Message
            }
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }

}
