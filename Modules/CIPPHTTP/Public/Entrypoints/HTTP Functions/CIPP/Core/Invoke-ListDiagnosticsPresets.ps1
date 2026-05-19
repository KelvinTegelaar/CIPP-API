function Invoke-ListDiagnosticsPresets {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    try {
        $Table = Get-CIPPTable -TableName 'DiagnosticsPresets'
        $Presets = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
            $Data = $_.data | ConvertFrom-Json
            [PSCustomObject]@{
                GUID  = $_.RowKey
                name  = $_.name
                query = $Data.query
            }
        }

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Presets)
        }
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                Error = "Failed to list diagnostics presets: $($_.Exception.Message)"
            }
        }
    }
}
