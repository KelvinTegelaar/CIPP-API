using namespace System.Net

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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
