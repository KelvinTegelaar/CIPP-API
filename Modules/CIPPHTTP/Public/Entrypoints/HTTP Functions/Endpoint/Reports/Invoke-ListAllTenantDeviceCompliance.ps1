Function Invoke-ListAllTenantDeviceCompliance {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Tenant.DeviceCompliance.Read
    .DESCRIPTION
        Lists device compliance summary across all managed tenants using the Lighthouse managedDeviceCompliances API, or for a single tenant via Intune.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ($TenantFilter -eq 'AllTenants') {
            # The Lighthouse aggregate returns every managed tenant with no per-caller scoping, so
            # narrow it to the tenants this caller is allowed to see (organizationId = customerId).
            $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances' | Select-CippAllowedTenantData -TenantProperty 'organizationId'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            # organizationId is the tenant's customerId, so a domain has to be resolved first
            $CustomerId = (Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1).customerId ?? $TenantFilter
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances?`$top=999&`$filter=organizationId eq '$CustomerId'"
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = "Could not connect to Azure Lighthouse API: $($ErrorMessage)"
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
