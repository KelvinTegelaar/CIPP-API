function Invoke-ExecDeviceAction {
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


    # Interact with Body parameters or the body of the request.
    $Action = $Request.Body.Action
    $DeviceFilter = $Request.Body.GUID
    $TenantFilter = $Request.Body.tenantFilter

    try {
        switch ($Action) {
            'setDeviceName' {
                if ($Request.Body.input -match '%') {
                    $Device = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceFilter" -tenantid $TenantFilter
                    $Request.Body.input = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Request.Body.input
                    $Request.Body.input = $Request.Body.input -replace '%SERIAL%', $Device.serialNumber
                    # limit to 15 characters
                    if ($Request.Body.input.Length -gt 15) {
                        $Request.Body.input = $Request.Body.input.Substring(0, 15)
                    }
                }

                $ActionBody = @{ deviceName = $Request.Body.input } | ConvertTo-Json -Compress
                break
            }
            'users' {
                $ActionBody = @{ '@odata.id' = "https://graph.microsoft.com/beta/users('$($Request.Body.user.value)')" } | ConvertTo-Json -Compress
                Write-Host "ActionBody: $ActionBody"
                break
            }
            default { $ActionBody = $Request.Body | ConvertTo-Json -Compress }
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

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
