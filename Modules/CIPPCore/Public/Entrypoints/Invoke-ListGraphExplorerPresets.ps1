using namespace System.Net

function Invoke-ListGraphExplorerPresets {
    <#
    .SYNOPSIS
    List Graph Explorer presets for the current user
    
    .DESCRIPTION
    Retrieves Graph Explorer presets that belong to the current user or are shared with them, with optional filtering by endpoint.
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Tools
    Summary: List Graph Explorer Presets
    Description: Retrieves Graph Explorer presets that belong to the current user or are shared with them, with optional filtering by endpoint. Supports both personal and shared presets.
    Tags: Tools,Graph Explorer,Presets
    Parameter: Endpoint (string) [query] - Optional endpoint filter to show only presets for a specific endpoint
    Response: Returns an object with the following properties:
    Response: - Results (array): Array of preset objects with the following properties:
    Response: - id (string): Preset unique identifier
    Response: - name (string): Preset display name
    Response: - IsShared (boolean): Whether the preset is shared with other users
    Response: - IsMyPreset (boolean): Whether the preset belongs to the current user
    Response: - params (object): Preset parameters and configuration
    Response: - Metadata (object): Contains Count of presets returned
    Example: {
      "Results": [
        {
          "id": "preset-123",
          "name": "User Management",
          "IsShared": true,
          "IsMyPreset": false,
          "params": {
            "endpoint": "/users",
            "method": "GET",
            "headers": {}
          }
        }
      ],
      "Metadata": {
        "Count": 1
      }
    }
    Error: Returns empty results array if the operation fails to retrieve presets.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Username = $Request.Headers['x-ms-client-principal-name']

    try {
        $Table = Get-CIPPTable -TableName 'GraphPresets'
        $Presets = Get-CIPPAzDataTableEntity @Table | Where-Object { $Username -eq $_.Owner -or $_.IsShared -eq $true } | Sort-Object -Property name
        $Results = foreach ($Preset in $Presets) {
            [PSCustomObject]@{
                id         = $Preset.Id
                name       = $Preset.name
                IsShared   = $Preset.IsShared
                IsMyPreset = $Preset.Owner -eq $Username
                params     = (ConvertFrom-Json -InputObject $Preset.Params)
            }
        }

        if ($Request.Query.Endpoint) {
            $Endpoint = $Request.Query.Endpoint -replace '^/', ''
            $Results = $Results | Where-Object { ($_.params.endpoint -replace '^/', '') -eq $Endpoint }
        }
    }
    catch {
        Write-Warning "Could not list presets. $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $Results = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($Results)
                Metadata = @{
                    Count = ($Results | Measure-Object).Count
                }
            }
        })
}
