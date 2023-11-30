using namespace System.Net

Function Invoke-ListApps {
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
        $TenantFilter = $Request.Query.TenantFilter
        try {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$top=999&`$filter=(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&`$orderby=displayName&" -tenantid $TenantFilter
                $StatusCode = [HttpStatusCode]::OK
        } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $StatusCode = [HttpStatusCode]::Forbidden
                $GraphRequest = $ErrorMessage
        }

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body       = @($GraphRequest)
                })

}
