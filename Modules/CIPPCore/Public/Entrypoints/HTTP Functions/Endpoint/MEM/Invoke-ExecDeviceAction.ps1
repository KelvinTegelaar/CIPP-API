using namespace System.Net

Function Invoke-ExecDeviceAction {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with Body parameters or the body of the request.


    try {
        if ($Request.Body.Action -eq 'setDeviceName') {
            $ActionBody = @{ deviceName = $Request.Body.input } | ConvertTo-Json -Compress
        }
        else {
            $ActionBody = $Request.Body | ConvertTo-Json -Compress
        }

        $cmdparams = @{
            Action = $Request.Body.Action
            ActionBody = $ActionBody
            DeviceFilter = $Request.Body.GUID
            TenantFilter = $Request.Body.TenantFilter
            Headers = $Request.Headers
            APINAME = $APINAME
        }
        $ActionResult = New-CIPPDeviceAction @cmdparams

        $body = [pscustomobject]@{'Results' = "$ActionResult" }

    } catch {
        $body = [pscustomobject]@{'Results' = "Failed to queue action $action on $DeviceFilter $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
