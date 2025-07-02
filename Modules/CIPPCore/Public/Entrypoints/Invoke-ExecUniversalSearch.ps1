using namespace System.Net

function Invoke-ExecUniversalSearch {
    <#
    .SYNOPSIS
    Execute universal search across all managed tenants
    
    .DESCRIPTION
    Performs universal search across all managed tenants using Microsoft Graph API and Azure Lighthouse to find users by display name or user principal name
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Search
    Summary: Exec Universal Search
    Description: Performs universal search across all managed tenants using Microsoft Graph API and Azure Lighthouse to find users by display name or user principal name with partial matching
    Tags: Search,Universal,Graph API,Lighthouse
    Parameter: name (string) [query] - Search term to find users by display name or user principal name
    Response: Returns an array of user objects found across all managed tenants
    Response: Each user object contains standard user properties including:
    Response: - _TenantId (string): Tenant ID where the user was found
    Response: - userPrincipalName (string): User's principal name
    Response: - displayName (string): User's display name
    Response: - id (string): User's unique identifier
    Response: On error: Returns error message with HTTP 403 status
    Example: [
      {
        "_TenantId": "12345678-1234-1234-1234-123456789012",
        "userPrincipalName": "john.doe@contoso.com",
        "displayName": "John Doe",
        "id": "87654321-4321-4321-4321-210987654321"
      },
      {
        "_TenantId": "87654321-4321-4321-4321-210987654321",
        "userPrincipalName": "john.doe@fabrikam.com",
        "displayName": "John Doe",
        "id": "12345678-1234-1234-1234-123456789012"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'




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
        }
        else {
            $GraphRequest = $GraphRequest.result.Results | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_.'_TenantId' -in $tenantfilter.customerId }
        }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
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
