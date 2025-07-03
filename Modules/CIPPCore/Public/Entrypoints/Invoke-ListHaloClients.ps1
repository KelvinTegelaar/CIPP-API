using namespace System.Net

function Invoke-ListHaloClients {
    <#
    .SYNOPSIS
    List HaloPSA clients from the PSA integration
    
    .DESCRIPTION
    Retrieves a list of clients from HaloPSA using the configured integration settings with pagination support
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
        
    .NOTES
    Group: Extensions
    Summary: List Halo Clients
    Description: Retrieves a list of clients from HaloPSA using the configured integration settings with pagination support and token-based authentication
    Tags: Extensions,HaloPSA,PSA,Clients
    Response: Returns an array of HaloPSA client objects with the following properties:
    Response: - label (string): Client name for display
    Response: - value (string): Client ID for programmatic use
    Response: On success: Array of client objects with HTTP 200 status
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "label": "Contoso Corporation",
        "value": "123"
      },
      {
        "label": "Fabrikam Inc",
        "value": "456"
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
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
        $Token = Get-HaloToken -configuration $Configuration
        $i = 1
        $RawHaloClients = do {
            $Result = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Client?page_no=$i&page_size=999&pageinate=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
            $Result.clients | Select-Object * -ExcludeProperty logo
            $i++
            $PageCount = [Math]::Ceiling($Result.record_count / 999)
        } while ($i -le $PageCount)
        $HaloClients = $RawHaloClients | ForEach-Object {
            [PSCustomObject]@{
                label = $_.name
                value = $_.id
            }
        }
        Write-Host "Found $($HaloClients.Count) Halo Clients"
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $HaloClients = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($HaloClients)
        })

}
