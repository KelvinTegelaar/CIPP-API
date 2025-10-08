Function Invoke-ListAppStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $appFilter = $Request.Query.AppFilter
    Write-Host "Using $appFilter"
    $body = @"
{"select":["DeviceName","UserPrincipalName","Platform","AppVersion","InstallState","InstallStateDetail","LastModifiedDateTime","DeviceId","ErrorCode","UserName","UserId","ApplicationId","AssignmentFilterIdsList","AppInstallState","AppInstallStateDetails","HexErrorCode"],"skip":0,"top":999,"filter":"(ApplicationId eq '$Appfilter')","orderBy":[]}
"@
    try {
        $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getDeviceInstallStatusReport' -tenantid $TenantFilter -body $body
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
