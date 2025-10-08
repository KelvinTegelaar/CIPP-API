Function Invoke-ExecDeviceDelete {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with body parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $Action = $Request.Body.action ?? $Request.Query.action
    $DeviceID = $Request.Body.ID ?? $Request.Query.ID

    try {
        $Results = Set-CIPPDeviceState -Action $Action -DeviceID $DeviceID -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
