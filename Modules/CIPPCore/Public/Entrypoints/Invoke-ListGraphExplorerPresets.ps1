using namespace System.Net

Function Invoke-ListGraphExplorerPresets {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Username = $Request.Headers['x-ms-client-principal-name']

    try {
        $Table = Get-CIPPTable -TableName 'GraphPresets'
        $Presets = Get-CIPPAzDataTableEntity @Table -Filter "Owner eq '$Username' or IsShared eq true" | Sort-Object -Property name
        $Results = foreach ($Preset in $Presets) {
            [PSCustomObject]@{
                id         = $Preset.Id
                name       = $Preset.name
                IsShared   = $Preset.IsShared
                IsMyPreset = $Preset.Owner -eq $Username
                params     = ConvertFrom-Json -InputObject $Preset.Params
            }
        }

        if ($Request.Query.Endpoint) {
            $Endpoint = $Request.Query.Endpoint -replace '^/', ''
            $Results = $Results | Where-Object { ($_.params.endpoint -replace '^/', '') -eq $Endpoint }
        }
    } catch {
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
