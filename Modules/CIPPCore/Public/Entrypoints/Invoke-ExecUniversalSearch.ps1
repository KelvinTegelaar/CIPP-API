using namespace System.Net

Function Invoke-ExecUniversalSearch {
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

    try {
        $tenantfilter = Get-Tenants
        $payload = '{ "returnsPartialResults":true, "displayName":"getUsers", "target": { "allTenants":true }, "operationDefinition": { "values":["@sys.normalize([ConsistencyLevel: eventual GET /v1.0/users?$top=5&$search=\"userPrincipalName:' + $request.query.name + '\" OR \"displayName:' + $request.query.name + '\"])"] }, "aggregationDefinition": { "values":["@sys.append([/result],50)"] } }'
        $GraphRequest = (New-GraphPOSTRequest -noauthcheck $true -type 'POST' -uri 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedTenantOperations' -tenantid $env:TenantID -body $payload).result.Results | ConvertFrom-Json | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = "Could not connect to Azure Lighthouse API: $($ErrorMessage)"
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
