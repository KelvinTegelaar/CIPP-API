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
    try {
        $GraphRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$expand=windowsProtectionState&`$select=id,deviceName,deviceType,operatingSystem,windowsProtectionState"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = "$($ErrorMessage)"
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
