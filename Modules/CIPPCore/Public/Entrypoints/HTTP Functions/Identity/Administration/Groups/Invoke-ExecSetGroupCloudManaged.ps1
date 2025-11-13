function Invoke-ExecSetGroupCloudManaged {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    .DESCRIPTION
        Sets the cloud-managed status of a group.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $GroupID = $Request.Body.ID
    $DisplayName = $Request.Body.displayName
    $IsCloudManaged = [System.Convert]::ToBoolean($Request.Body.isCloudManaged)

    try {
        $Result = Set-CIPPGroupCloudManaged -Id $GroupID -TenantFilter $TenantFilter -DisplayName $DisplayName -IsCloudManaged $IsCloudManaged -APIName $APIName -Headers $Headers
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
