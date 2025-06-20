using namespace System.Net

Function Invoke-ListSharepointSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    #  XXX - Seems to be an unused endpoint? -Bobby


    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenantFilter
    $Request = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings'

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Request)
        })

}
