using namespace System.Net

Function Invoke-ExecGraphExplorerPreset {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Action = $Request.Body.Action ?? ''

    switch ($Action) {
        'Copy' {
            $Id = (New-Guid).Guid
        }
        'Save' {
            $Id = $Request.Body.preset.reportTemplate.value
        }
        'Delete' {
            $Id = $Request.Body.preset.reportTemplate.value
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
            Add-CIPPAzDataTableEntity @Table -Entity $Preset
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
                Results = $Message
                Success = $Success
            }
        })
}
