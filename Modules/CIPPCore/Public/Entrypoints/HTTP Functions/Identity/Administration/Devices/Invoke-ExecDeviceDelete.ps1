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
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with body parameters or the body of the request.
    $TenantFilter = $Request.body.tenantFilter ?? $Request.Query.tenantFilter
    $Action = $Request.body.action ?? $Request.Query.action
    $DeviceID = $Request.body.ID ?? $Request.Query.ID

    try {
        $Results = Set-CIPPDeviceState -Action $Action -DeviceID $DeviceID -TenantFilter $TenantFilter -Headers $Request.Headers -APIName $APINAME
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    Write-Host $Results
    $body = [pscustomobject]@{'Results' = "$Results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
