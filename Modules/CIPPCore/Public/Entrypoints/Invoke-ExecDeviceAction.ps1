using namespace System.Net

Function Invoke-ExecDeviceAction {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.


    try {   
        if ($Request.Query.Action -eq 'setDeviceName') {
            $ActionBody = @{ deviceName = $Request.Body.input } | ConvertTo-Json -Compress
        }  
        $ActionResult = New-CIPPDeviceAction -Action $Request.Query.Action -ActionBody $ActionBody -DeviceFilter $Request.Query.GUID -TenantFilter $Request.Query.TenantFilter -ExecutingUser $request.headers.'x-ms-client-principal' -APINAME $APINAME
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
