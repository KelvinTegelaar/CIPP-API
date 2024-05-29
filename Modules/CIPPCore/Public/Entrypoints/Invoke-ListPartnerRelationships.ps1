using namespace System.Net

Function Invoke-ListPartnerRelationships {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $GraphRequestList = @{
            Endpoint            = 'policies/crossTenantAccessPolicy/partners'
            TenantFilter        = $Request.Query.TenantFilter
            QueueNameOverride   = 'Partner Relationships'
            ReverseTenantLookup = $true
        }
        $GraphRequest = Get-GraphRequestList @GraphRequestList
    } catch {
        $GraphRequest = @()
    }

    $StatusCode = [HttpStatusCode]::OK

    $results = [PSCustomObject]@{
        Results = @($GraphRequest)
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $results
        })

}
