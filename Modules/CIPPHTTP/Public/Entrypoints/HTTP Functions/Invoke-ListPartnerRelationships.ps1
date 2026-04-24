Function Invoke-ListPartnerRelationships {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequestList = @{
            Endpoint            = 'policies/crossTenantAccessPolicy/partners'
            TenantFilter        = $TenantFilter
            QueueNameOverride   = 'Partner Relationships'
            ReverseTenantLookup = $true
        }
        $GraphRequest = Get-GraphRequestList @GraphRequestList
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $GraphRequest = @()
        $StatusCode = [HttpStatusCode]::Forbidden
    }


    $Results = [PSCustomObject]@{
        Results = @($GraphRequest)
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        }
}
