using namespace System.Net

Function Invoke-ListUserPhoto {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $tenantFilter = $Request.Query.TenantFilter
    $userId = $Request.Query.UserID

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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = $ImageData.headers.'Content-Type'
            Body        = $Body
        })

}
