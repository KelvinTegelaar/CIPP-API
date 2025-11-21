function Invoke-ExecSetCloudManaged {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.DirSync.ReadWrite
    .DESCRIPTION
        Sets the cloud-managed status of a user, group, or contact.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $GroupID = $Request.Body.ID
    $DisplayName = $Request.Body.displayName
    $Type = $Request.Body.type
    $IsCloudManaged = [System.Convert]::ToBoolean($Request.Body.isCloudManaged)

    try {
        $Params = @{
            Id             = $GroupID
            TenantFilter   = $TenantFilter
            DisplayName    = $DisplayName
            Type           = $Type
            IsCloudManaged = $IsCloudManaged
            APIName        = $APIName
            Headers        = $Headers
        }
        $Result = Set-CIPPCloudManaged @Params
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
