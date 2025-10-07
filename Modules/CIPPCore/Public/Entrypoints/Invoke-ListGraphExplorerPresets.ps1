function Invoke-ListGraphExplorerPresets {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CIPPTable -TableName 'GraphPresets'
        $Presets = Get-CIPPAzDataTableEntity @Table | Where-Object { $Username -eq $_.Owner -or $_.IsShared -eq $true } | Sort-Object -Property name
        $Results = foreach ($Preset in $Presets) {
            [PSCustomObject]@{
                id         = $Preset.Id
                name       = $Preset.name
                IsShared   = $Preset.IsShared
                IsMyPreset = $Preset.Owner -eq $Username
                Owner      = $Preset.Owner
                params     = (ConvertFrom-Json -InputObject $Preset.Params)
            }
        }

        if ($Request.Query.Endpoint) {
            $Endpoint = $Request.Query.Endpoint -replace '^/', ''
            $Results = $Results | Where-Object { ($_.params.endpoint -replace '^/', '') -eq $Endpoint }
        }
    } catch {
        Write-Warning "Could not list presets. $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $Results = @()
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($Results)
                Metadata = @{
                    Count = ($Results | Measure-Object).Count
                }
            }
        })
}
