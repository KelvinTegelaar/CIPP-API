using namespace System.Net

Function Invoke-ListUserPhoto {
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
    $tenantFilter = $Request.Query.TenantFilter
    $userId = $Request.Query.UserID


    $URI = "https://graph.microsoft.com/v1.0/users/$userId/photos/240x240/`$value"
    Write-Host $URI
    $graphRequest = New-GraphGetRequest -uri $URI -tenantid $tenantFilter


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($graphRequest)
        })

}
