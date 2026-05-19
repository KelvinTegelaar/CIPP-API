Function Invoke-ListSharepointSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    #  XXX - Seems to be an unused endpoint? -Bobby


    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenantFilter
    $Request = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Request)
        })

}
