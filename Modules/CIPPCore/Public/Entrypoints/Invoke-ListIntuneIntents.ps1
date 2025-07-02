using namespace System.Net

function Invoke-ListIntuneIntents {
    <#
    .SYNOPSIS
    List Intune security intents and their configurations
    
    .DESCRIPTION
    Retrieves Microsoft Intune security intents including their settings and categories using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
        
    .NOTES
    Group: Device Management
    Summary: List Intune Intents
    Description: Retrieves Microsoft Intune security intents including their settings and categories using Microsoft Graph API for device management and security configuration
    Tags: Device Management,Intune,Security Intents,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns an array of Intune intent objects with the following properties:
    Response: - id (string): Intent unique identifier
    Response: - displayName (string): Intent display name
    Response: - description (string): Intent description
    Response: - templateId (string): Template identifier
    Response: - settings (array): Array of intent settings with configuration values
    Response: - categories (array): Array of intent categories
    Response: - isAssigned (boolean): Whether the intent is assigned
    Response: - lastModifiedDateTime (string): Last modification date and time
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "id": "12345678-1234-1234-1234-123456789012",
        "displayName": "Windows 10 Security Baseline",
        "description": "Security baseline for Windows 10 devices",
        "templateId": "template-123",
        "isAssigned": true,
        "lastModifiedDateTime": "2024-01-15T10:30:00Z",
        "settings": [
          {
            "id": "setting-123",
            "displayName": "Password Policy",
            "value": "enabled"
          }
        ],
        "categories": [
          {
            "id": "category-123",
            "displayName": "Security"
          }
        ]
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/Intents?`$expand=settings,categories" -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
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
