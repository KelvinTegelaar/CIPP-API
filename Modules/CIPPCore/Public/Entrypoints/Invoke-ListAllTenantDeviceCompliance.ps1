using namespace System.Net

function Invoke-ListAllTenantDeviceCompliance {
    <#
    .SYNOPSIS
    List device compliance information for all managed tenants
    
    .DESCRIPTION
    Retrieves device compliance information for all managed tenants or a specific tenant using Azure Lighthouse API and Microsoft Graph.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DeviceCompliance.Read
        
    .NOTES
    Group: Device Management
    Summary: List All Tenant Device Compliance
    Description: Retrieves device compliance information for all managed tenants or a specific tenant using Azure Lighthouse API and Microsoft Graph.
    Tags: Device Management,Compliance,Lighthouse,Graph API
    Parameter: TenantFilter (string) [query] - Target tenant identifier (use 'AllTenants' for all tenants)
    Response: Returns device compliance data from Microsoft Graph API
    Response: On success: Array of device compliance objects with HTTP 200 status
    Response: On no data: "No data found - This client might not be onboarded in Lighthouse" with HTTP 403 status
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "id": "12345678-1234-1234-1234-123456789012",
        "organizationId": "87654321-4321-4321-4321-210987654321",
        "deviceCompliancePolicyId": "device-policy-123",
        "deviceCompliancePolicyName": "Windows 10 Compliance Policy",
        "deviceCompliancePolicyVersion": 1,
        "deviceCompliancePolicyType": "windows10CompliancePolicy",
        "deviceCompliancePolicyStatus": "compliant",
        "deviceCompliancePolicyLastModifiedDateTime": "2024-01-15T10:30:00Z"
      }
    ]
    Error: Returns error details if the operation fails to connect to Azure Lighthouse API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'




    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ($TenantFilter -eq 'AllTenants') {
            $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances'
            $StatusCode = [HttpStatusCode]::OK
        }
        else {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances?`$top=999&`$filter=organizationId eq '$TenantFilter'"
            $StatusCode = [HttpStatusCode]::OK
        }

        if ($GraphRequest.value.count -lt 1) {
            $StatusCode = [HttpStatusCode]::Forbidden
            $GraphRequest = 'No data found - This client might not be onboarded in Lighthouse'
        }
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
