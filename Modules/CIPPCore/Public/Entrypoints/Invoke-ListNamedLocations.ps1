Function Invoke-ListNamedLocations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -Tenantid $tenantfilter | Select-Object *,
        @{
            name       = 'rangeOrLocation'
            expression = { if ($_.ipRanges) { $_.ipranges.cidrAddress -join ', ' } else { $_.countriesAndRegions -join ', ' } }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage

    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
