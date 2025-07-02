using namespace System.Net

function Invoke-ExecGraphExplorerPreset {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    $Action = $Request.Body.action ?? ''

    Write-Information ($Request.Body | ConvertTo-Json -Depth 10)

    switch ($Action) {
        'Copy' {
            $Id = $Request.Body.preset.id ? $Request.Body.preset.id : (New-Guid).Guid
        }
        'Save' {
            $Id = $Request.Body.preset.id
        }
        'Delete' {
            $Id = $Request.Body.preset.id
        }
        default {
            $Action = 'Copy'
            $Id = (New-Guid).Guid
        }
    }

    $params = $Request.Body.preset | Select-Object endpoint, '$filter', '$select', '$count', '$expand', '$search', NoPagination, '$top', IsShared

    if ($params.'$select'.value) {
        $params.'$select' = ($params.'$select').value -join ','
    }

    if (!$Request.Body.preset.name) {
        $Message = 'Error: Preset name is required'
        $StatusCode = [HttpStatusCode]::BadRequest
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @{
                    Results = @{
                        resultText = $Message
                        state      = 'error'
                    }
                }
            })
        return
    }

    if (!$Request.Body.preset.endpoint) {
        $Message = 'Error: Preset endpoint is required'
        $StatusCode = [HttpStatusCode]::BadRequest
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @{
                    Results = @{
                        resultText = $Message
                        state      = 'error'
                    }
                }
            })
        return
    }

    $Preset = [PSCustomObject]@{
        PartitionKey = 'Preset'
        RowKey       = [string]$Id
        id           = [string]$Id
        name         = [string]$Request.Body.preset.name
        Owner        = [string]$Username
        IsShared     = $Request.Body.preset.IsShared
        params       = [string](ConvertTo-Json -InputObject $params -Compress)
    }

    try {
        $Success = $false
        $Table = Get-CIPPTable -TableName 'GraphPresets'
        $Message = '{0} preset succeeded' -f $Action
        if ($Action -eq 'Copy') {
            Add-CIPPAzDataTableEntity @Table -Entity $Preset -Force
            $Success = $true
        } else {
            $Entity = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$Id'"
            if ($Entity.Owner -eq $Username ) {
                if ($Action -eq 'Delete') {
                    Remove-AzDataTableEntity -Force @Table -Entity $Entity
                } elseif ($Action -eq 'Save') {
                    Add-CIPPAzDataTableEntity @Table -Entity $Preset -Force
                }
                $Success = $true
            } else {
                Write-Host "username in table: $($Entity.Owner). Username in request: $Username"
                $Message = 'Error: You can only modify your own presets.'
                $Success = $false
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Success = $false
        $Message = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                Results = @{
                    resultText = $Message
                    state      = if ($Success) { 'success' } else { 'error' }
                }
            }
        })
}
