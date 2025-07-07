using namespace System.Net

function Invoke-ListDefenderState {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$expand=windowsProtectionState&`$select=id,deviceName,deviceType,operatingSystem,windowsProtectionState"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $GraphRequest = "$($ErrorMessage)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
