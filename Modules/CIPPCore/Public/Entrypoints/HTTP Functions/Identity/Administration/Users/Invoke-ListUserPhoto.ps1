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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $tenantFilter = $Request.Query.TenantFilter
    $userId = $Request.Query.UserID


    $URI = "/users/$userId/photo/`$value"
    Write-Host $URI
    #$ImageData = New-GraphGetRequest -uri $URI -tenantid $tenantFilter -noPagination $true
    #Write-Host $ImageData

    $Requests = @(
        @{
            id     = 'photo'
            url    = $URI
            method = 'GET'
        }
    )

    $ImageData = New-GraphBulkRequest -Requests $Requests -tenantid $tenantFilter
    #convert body from base64 to byte array
    $Body = [Convert]::FromBase64String($ImageData.body)

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = $ImageData.headers.'Content-Type'
            Body        = $Body
        })

}
