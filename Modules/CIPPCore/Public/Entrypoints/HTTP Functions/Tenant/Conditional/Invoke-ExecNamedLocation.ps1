using namespace System.Net

Function Invoke-ExecNamedLocation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $NamedLocationId = $Request.Body.NamedLocationId ?? $Request.Query.NamedLocationId
    $change = $Request.Body.change ?? $Request.Query.change
    $content = $Request.Body.input ?? $Request.Query.input

    try {
        $results = Set-CIPPNamedLocation -NamedLocationId $NamedLocationId -TenantFilter $TenantFilter -change $change -content $content -Headers $Request.Headers
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to edit named location: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $results = "Failed to edit named location. Error: $($ErrorMessage.NormalizedError)"
    }


    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
