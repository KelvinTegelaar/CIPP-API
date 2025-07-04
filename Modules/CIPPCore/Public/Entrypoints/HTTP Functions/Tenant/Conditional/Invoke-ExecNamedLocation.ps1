using namespace System.Net

function Invoke-ExecNamedLocation {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $NamedLocationId = $Request.Body.namedLocationId ?? $Request.Query.namedLocationId
    $Change = $Request.Body.change ?? $Request.Query.change
    $Content = $Request.Body.input ?? $Request.Query.input

    try {
        $Results = Set-CIPPNamedLocation -NamedLocationId $NamedLocationId -TenantFilter $TenantFilter -Change $Change -Content $Content -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = $_.Exception.Message
        $Results = "Failed to edit named location. Error: $ErrorMessage"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
