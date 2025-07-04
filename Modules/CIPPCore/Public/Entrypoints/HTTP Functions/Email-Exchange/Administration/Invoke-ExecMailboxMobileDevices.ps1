using namespace System.Net

function Invoke-ExecMailboxMobileDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # XXX - Seems to be an unused endpoint. -Bobby
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserId = $Request.Query.UserID ?? $Request.Body.UserID
    $Guid = $Request.Query.GUID ?? $Request.Body.GUID
    $DeviceId = $Request.Query.DeviceID ?? $Request.Body.DeviceID
    $Quarantine = $Request.Query.Quarantine ?? $Request.Body.Quarantine
    $Delete = $Request.Query.Delete ?? $Request.Body.Delete

    try {
        $Results = Set-CIPPMobileDevice -UserId $UserId -Guid $Guid -DeviceId $DeviceId -Quarantine $Quarantine -TenantFilter $TenantFilter -APIName $APIName -Delete $Delete -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }

}
