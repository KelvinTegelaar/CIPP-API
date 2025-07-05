using namespace System.Net

function Invoke-ListNamedLocations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'




    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -Tenantid $TenantFilter | Select-Object *,
        @{
            name       = 'rangeOrLocation'
            expression = { if ($_.ipRanges) { $_.ipRanges.cidrAddress -join ', ' } else { $_.countriesAndRegions -join ', ' } }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage

    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
