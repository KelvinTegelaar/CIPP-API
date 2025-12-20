Function Invoke-ExecUniversalSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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
        $GraphRequest = New-GraphPOSTRequest -noauthcheck $true -type 'POST' -uri 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedTenantOperations' -tenantid $env:TenantID -body $payload -IgnoreErrors $true
        if (!$GraphRequest.result.results) {
            $GraphRequest = ($GraphRequest.error.message | ConvertFrom-Json).result.results | ConvertFrom-Json | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        } else {
            $GraphRequest = $GraphRequest.result.Results | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = "Could not connect to Azure Lighthouse API: $($ErrorMessage)"
    }
    return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }

}
