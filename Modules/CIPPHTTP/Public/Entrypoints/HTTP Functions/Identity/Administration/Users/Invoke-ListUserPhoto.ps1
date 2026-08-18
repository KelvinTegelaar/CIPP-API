Function Invoke-ListUserPhoto {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Retrieves the profile photo for a specific Entra ID user, returned as a base64-encoded image.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $tenantFilter = $Request.Query.tenantFilter
    $userId = $Request.Query.UserID

    # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $tenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = 'Access to this tenant is not allowed'
            })
    }

    $URI = "/users/$userId/photo/`$value"

    $Requests = @(
        @{
            id     = 'photo'
            url    = $URI
            method = 'GET'
        }
    )

    $ImageData = New-GraphBulkRequest -Requests $Requests -tenantid $tenantFilter -NoAuthCheck $true
    #convert body from base64 to byte array
    $Body = [Convert]::FromBase64String($ImageData.body)

    return ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = $ImageData.headers.'Content-Type'
            Body        = $Body
        })

}
