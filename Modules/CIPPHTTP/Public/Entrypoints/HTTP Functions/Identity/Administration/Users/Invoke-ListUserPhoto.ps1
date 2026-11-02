Function Invoke-ListUserPhoto {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Retrieves an Entra ID user's profile photo as an image. With tenantFilter and UserID it returns that
        user's photo, which needs access to the tenant. Without tenantFilter it returns the signed-in user's own photo.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $tenantFilter = $Request.Query.tenantFilter

    if ($tenantFilter) {
        $userId = $Request.Query.UserID
        if (-not $userId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = 'UserID is required with tenantFilter'
                })
        }
        # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $tenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = 'Access to this tenant is not allowed'
                })
        }
    } else {
        # The caller's own photo: the user comes from the sign-in, never the request.
        $userId = $Request.Headers.'x-ms-client-principal-name'
        $tenantFilter = $env:TenantID
        if (-not $userId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'No photo found for this user'
                })
        }
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
    if ($ImageData.status -ne 200 -or $ImageData.body -isnot [string]) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = 'No photo found for this user'
            })
    }
    #convert body from base64 to byte array
    $Body = [Convert]::FromBase64String($ImageData.body)

    return ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = $ImageData.headers.'Content-Type'
            Body        = $Body
        })

}
