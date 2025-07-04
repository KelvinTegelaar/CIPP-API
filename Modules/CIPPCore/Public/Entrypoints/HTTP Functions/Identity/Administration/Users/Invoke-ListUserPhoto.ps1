using namespace System.Net

function Invoke-ListUserPhoto {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $tenantFilter = $Request.Query.tenantFilter
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

    return @{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = $ImageData.headers.'Content-Type'
        Body        = $Body
    }
}
