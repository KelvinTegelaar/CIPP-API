using namespace System.Net

Function Invoke-ExecUniversalSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
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
        $payload = [PSCustomObject]@{
            returnsPartialResults = $false
            displayName           = 'getUsers'
            target                = [PSCustomObject]@{
                allTenants = $true
            }
            operationDefinition   = [PSCustomObject]@{
                values = @(
                    "@sys.normalize([ConsistencyLevel: eventual GET /v1.0/users?`$top=5&`$search=`"userPrincipalName:$($Request.query.name)`" OR `"displayName:$($Request.query.name)`"])"
                )
            }
            aggregationDefinition = [PSCustomObject]@{
                values = @(
                    '@sys.append([/result],50)'
                )
            }
        } | ConvertTo-Json -Depth 10
        $GraphRequest = (New-GraphPOSTRequest -noauthcheck $true -type 'POST' -uri 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedTenantOperations' -tenantid $env:TenantID -body $payload -IgnoreErrors $true)
        if (!$GraphRequest.result.results) {
            $GraphRequest = ($GraphRequest.error.message | ConvertFrom-Json).result.results | ConvertFrom-Json | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        } else {
            $GraphRequest.result.Results | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        }
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
