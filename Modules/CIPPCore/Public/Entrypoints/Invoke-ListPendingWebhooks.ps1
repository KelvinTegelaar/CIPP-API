using namespace System.Net

function Invoke-ListPendingWebhooks {
    <#
    .SYNOPSIS
    List pending webhook notifications
    
    .DESCRIPTION
    Retrieves pending webhook notifications from the webhook queue, processing JSON properties for proper formatting.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
        
    .NOTES
    Group: Webhooks
    Summary: List Pending Webhooks
    Description: Retrieves pending webhook notifications from the webhook queue, processing JSON properties for proper formatting and excluding system properties.
    Tags: Webhooks,Notifications,Queue
    Response: Returns an object with the following properties:
    Response: - Results (array): Array of webhook objects with processed JSON properties
    Response: - Metadata (object): Contains Count of webhooks returned
    Response: On success: Array of webhook objects with HTTP 200 status
    Response: On error: Empty array with HTTP 200 status
    Example: {
      "Results": [
        {
          "id": "webhook-123",
          "type": "security.breach",
          "data": {
            "tenantId": "12345678-1234-1234-1234-123456789012",
            "breachType": "password",
            "severity": "high"
          },
          "timestamp": "2024-01-15T10:30:00Z"
        }
      ],
      "Metadata": {
        "Count": 1
      }
    }
    Error: Returns empty results array if the operation fails to retrieve webhooks.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $Table = Get-CIPPTable -TableName 'WebhookIncoming'
        $Webhooks = Get-CIPPAzDataTableEntity @Table
        $Results = $Webhooks | Select-Object -ExcludeProperty RowKey, PartitionKey, ETag, Timestamp
        $PendingWebhooks = foreach ($Result in $Results) {
            foreach ($Property in $Result.PSObject.Properties.Name) {
                if (Test-Json -Json $Result.$Property -ErrorAction SilentlyContinue) {
                    $Result.$Property = $Result.$Property | ConvertFrom-Json
                }
            }
            $Result
        }
    }
    catch {
        $PendingWebhooks = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($PendingWebhooks)
                Metadata = @{
                    Count = ($PendingWebhooks | Measure-Object).Count
                }
            }
        })
}
