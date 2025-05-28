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
    $Action = $Request.Body.Action
    $DeviceFilter = $Request.Body.GUID
    $TenantFilter = $Request.Body.tenantFilter

    try {
        switch ($Action) {
            'setDeviceName' {
                $ActionBody = @{ deviceName = $Request.Body.input } | ConvertTo-Json -Compress
                break
            }
            'users' {
                $ActionBody = @{ '@odata.id' = "https://graph.microsoft.com/beta/users('$($Request.Body.user.value)')" } | ConvertTo-Json -Compress
                Write-Host "ActionBody: $ActionBody"
                break
            }
            Default { $ActionBody = $Request.Body | ConvertTo-Json -Compress }
        }

        $cmdParams = @{
            Action       = $Action
            ActionBody   = $ActionBody
            DeviceFilter = $DeviceFilter
            TenantFilter = $TenantFilter
            Headers      = $Headers
            APINAME      = $APIName
        }
        $ActionResult = New-CIPPDeviceAction @cmdParams

        $StatusCode = [HttpStatusCode]::OK
        $Results = "$ActionResult"

    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = "$($_.Exception.Message)"
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
