Function Invoke-ListDefenderState {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $StatusCode = [HttpStatusCode]::OK

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $DeviceID = $Request.Query.DeviceID

    try {
        # If DeviceID is provided, get Defender state for that specific device
        if ($DeviceID) {
            $GraphRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($DeviceID)?`$expand=windowsProtectionState&`$select=id,deviceName,deviceType,operatingSystem,windowsProtectionState"
        }
        # If no DeviceID is provided, get Defender state for all devices
        else {
            $GraphRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$expand=windowsProtectionState&`$select=id,deviceName,deviceType,operatingSystem,windowsProtectionState"
        }

        # Ensure we return an array even if single device
        if ($GraphRequest -and -not ($GraphRequest -is [array])) {
            $GraphRequest = @($GraphRequest)
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::OK
        $GraphRequest = "$($ErrorMessage)"
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
