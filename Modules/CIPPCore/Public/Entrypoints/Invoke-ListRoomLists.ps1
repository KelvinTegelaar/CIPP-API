using namespace System.Net

Function Invoke-ListRoomLists {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter

    try {
        $params = @{
            uri      = 'https://graph.microsoft.com/beta/places/microsoft.graph.roomlist'
            tenantid = $TenantFilter
            AsApp    = $true
        }
        $GraphRequest = New-GraphGetRequest @params

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest | Sort-Object displayName)
        })

}
