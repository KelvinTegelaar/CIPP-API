using namespace System.Net

function Invoke-ListOrg {
    <#
    .SYNOPSIS
    List organization information for a tenant
    
    .DESCRIPTION
    Retrieves organization information for a specific tenant using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Tenant Management
    Summary: List Org
    Description: Retrieves organization information for a specific tenant using Microsoft Graph API including organization details and properties
    Tags: Tenant Management,Organization,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier (use 'AllTenants' for all tenants)
    Response: Returns organization information from Microsoft Graph API
    Response: For AllTenants: Returns empty array
    Response: For specific tenant: Returns organization object with tenant details
    Response: Example: {
      "id": "12345678-1234-1234-1234-123456789012",
      "displayName": "Contoso Corporation",
      "businessPhones": ["+1-555-123-4567"],
      "street": "123 Main Street",
      "city": "Seattle",
      "state": "WA",
      "postalCode": "98101",
      "country": "United States",
      "defaultUsageLocation": "US",
      "technicalNotificationMails": ["admin@contoso.com"],
      "marketingNotificationEmails": [],
      "tenantType": "AAD",
      "createdDateTime": "2020-01-01T00:00:00Z"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') {
        $GraphRequest = @()
    }
    else {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })

}
