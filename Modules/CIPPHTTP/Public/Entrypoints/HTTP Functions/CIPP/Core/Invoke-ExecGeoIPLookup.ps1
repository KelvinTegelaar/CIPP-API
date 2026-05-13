Function Invoke-ExecGeoIPLookup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $IP = $Request.Query.IP ?? $Request.Body.IP

    if (-not $IP) {
        $ErrorMessage = Get-NormalizedError -Message 'IP address is required'
        $LocationInfo = $ErrorMessage
    } else {
        $locationInfo = Get-CIPPGeoIPLocation -IP $IP
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $LocationInfo
        })

}
