using namespace System.Net

function Invoke-ListPartnerRelationships {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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


    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($GraphRequest) }
    }
}
