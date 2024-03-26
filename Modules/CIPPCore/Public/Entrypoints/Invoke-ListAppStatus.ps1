using namespace System.Net

Function Invoke-ListAppStatus {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $tenantfilter = $Request.Query.TenantFilter
    $appFilter = $Request.Query.AppFilter
    Write-Host "Using $appFilter"
    $body = @"
{"select":["DeviceName","UserPrincipalName","Platform","AppVersion","InstallState","InstallStateDetail","LastModifiedDateTime","DeviceId","ErrorCode","UserName","UserId","ApplicationId","AssignmentFilterIdsList","AppInstallState","AppInstallStateDetails","HexErrorCode"],"skip":0,"top":999,"filter":"(ApplicationId eq '$Appfilter')","orderBy":[]}
"@
    try {
        $GraphRequest = New-Graphpostrequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getDeviceInstallStatusReport' -tenantid $TenantFilter -body $body
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
