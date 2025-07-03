using namespace System.Net

function Invoke-ListExtensionsConfig {
    <#
    .SYNOPSIS
    List CIPP extensions configuration
    
    .DESCRIPTION
    Retrieves the configuration for CIPP extensions including PSA integrations, webhook settings, and custom integrations.
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.Read
        
    .NOTES
    Group: Extensions
    Summary: List Extensions Config
    Description: Retrieves the configuration for CIPP extensions including PSA integrations like HaloPSA, webhook settings, and other custom integrations.
    Tags: Extensions,Configuration,PSA
    Response: Returns a configuration object with the following properties:
    Response: - HaloPSA (object): HaloPSA integration configuration including ticket type settings
    Response: - NinjaOne (object): NinjaOne integration configuration
    Response: - Hudu (object): Hudu integration configuration
    Response: - Webhooks (object): Webhook configuration settings
    Response: - Other integrations (object): Configuration for other enabled extensions
    Response: When HaloPSA.TicketType is configured, it includes:
    Response: - label (string): Display name of the ticket type
    Response: - value (string): Ticket type identifier
    Example: {
      "HaloPSA": {
        "enabled": true,
        "apiKey": "encrypted-api-key",
        "url": "https://contoso.halopsa.com",
        "TicketType": {
          "label": "Security Incident",
          "value": "123"
        }
      },
      "NinjaOne": {
        "enabled": false,
        "apiKey": "",
        "url": ""
      },
      "Webhooks": {
        "enabled": true,
        "endpoints": [
          "https://webhook.site/123456"
        ]
      }
    }
    Error: Returns error details if the operation fails to retrieve extension configuration.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Body = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        if ($Body.HaloPSA.TicketType -and !$Body.HaloPSA.TicketType.value) {
            # translate ticket type to autocomplete format
            Write-Information "Ticket Type: $($Body.HaloPSA.TicketType)"
            $Types = Get-HaloTicketType
            $Type = $Types | Where-Object { $_.id -eq $Body.HaloPSA.TicketType }
            #Write-Information ($Type | ConvertTo-Json)
            if ($Type) {
                $Body.HaloPSA.TicketType = @{
                    label = $Type.name
                    value = $Type.id
                }
            }
        }
    }
    catch {
        Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
        $Body = @{}
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
