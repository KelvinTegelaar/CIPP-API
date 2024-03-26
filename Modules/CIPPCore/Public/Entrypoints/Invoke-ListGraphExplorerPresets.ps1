using namespace System.Net

Function Invoke-ListGraphExplorerPresets {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {
        $Table = Get-CIPPTable -TableName 'GraphPresets'
        $Presets = Get-CIPPAzDataTableEntity @Table -Filter "Owner eq '$Username' or IsShared eq true"
        $Results = foreach ($Preset in $Presets) {
            [PSCustomObject]@{
                id         = $Preset.Id
                name       = $Preset.name
                IsShared   = $Preset.IsShared
                IsMyPreset = $Preset.Owner -eq $Username
                params     = ConvertFrom-Json -InputObject $Preset.Params
            }
        }
    } catch {
        $Presets = @()
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($Results)
                Metadata = @{
                    Count = ($Presets | Measure-Object).Count
                }
            }
        })
}
