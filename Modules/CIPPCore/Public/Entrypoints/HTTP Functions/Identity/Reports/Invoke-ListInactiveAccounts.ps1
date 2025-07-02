using namespace System.Net

function Invoke-ListInactiveAccounts {
    <#
    .SYNOPSIS
    List inactive user accounts across managed tenants
    
    .DESCRIPTION
    Retrieves inactive user accounts across managed tenants using Azure Lighthouse API and Microsoft Graph
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
        
    .NOTES
    Group: Identity Management
    Summary: List Inactive Accounts
    Description: Retrieves inactive user accounts across managed tenants using Azure Lighthouse API and Microsoft Graph for user lifecycle management and cleanup
    Tags: Identity,Inactive Accounts,Lighthouse,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier (use 'AllTenants' for all tenants)
    Response: Returns an array of inactive user objects with the following properties:
    Response: - id (string): User unique identifier
    Response: - userPrincipalName (string): User principal name
    Response: - displayName (string): User display name
    Response: - tenantId (string): Tenant identifier where the user is inactive
    Response: - lastSignInDateTime (string): Last sign-in date and time
    Response: - isInactive (boolean): Whether the user is inactive
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "id": "12345678-1234-1234-1234-123456789012",
        "userPrincipalName": "inactive.user@contoso.com",
        "displayName": "Inactive User",
        "tenantId": "87654321-4321-4321-4321-210987654321",
        "lastSignInDateTime": "2023-01-15T10:30:00Z",
        "isInactive": true
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Convert the TenantFilter parameter to a list of tenant IDs for AllTenants or a single tenant ID
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') {
        $TenantFilter = (Get-Tenants).customerId
    }
    else {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
    }

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/inactiveUsers?`$count=true" -tenantid $env:TenantID | Where-Object { $_.tenantId -in $TenantFilter }
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
