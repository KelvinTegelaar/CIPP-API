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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $NamedLocationId = $Request.Body.namedLocationId ?? $Request.Query.namedLocationId
    $Change = $Request.Body.change ?? $Request.Query.change
    $Content = $Request.Body.input ?? $Request.Query.input
    #reintroduced because iut can come from autocomplete OR textinput.
    if ($content.value) { $content = $content.value }


    try {
        $Results = Set-CIPPNamedLocation -NamedLocationId $NamedLocationId -TenantFilter $TenantFilter -Change $Change -Content $Content -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to edit named location: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $Results = "Failed to edit named location. Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Results) }
        })

}
