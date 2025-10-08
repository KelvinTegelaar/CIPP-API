Function Invoke-ListInactiveAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Convert the TenantFilter parameter to a list of tenant IDs for AllTenants or a single tenant ID
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') {
        $TenantFilter = (Get-Tenants).customerId
    } else {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
    }

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/inactiveUsers?`$count=true" -tenantid $env:TenantID | Where-Object { $_.tenantId -in $TenantFilter }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = "Could not connect to Azure Lighthouse API: $($ErrorMessage)"
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
