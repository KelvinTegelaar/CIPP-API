using namespace System.Net

Function Invoke-ExecNamedLocation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.Body.TenantFilter
    $NamedLocationId = $Request.Body.NamedLocationId
    $change = $Request.Body.change
    $content = $Request.Body.input

    try {
        $results = Set-CIPPNamedLocation -NamedLocationId $NamedLocationId -TenantFilter $TenantFilter -change $change -content $content -ExecutingUser $request.headers.'x-ms-client-principal'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -message "Failed to edit named location: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $results = "Failed to edit named location. Error: $($ErrorMessage.NormalizedError)"
    }


    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
