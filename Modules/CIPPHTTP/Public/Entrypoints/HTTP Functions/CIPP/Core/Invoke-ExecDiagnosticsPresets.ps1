function Invoke-ExecDiagnosticsPresets {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    try {
        $Table = Get-CIPPTable -TableName 'DiagnosticsPresets'
        $Action = $Request.Body.action
        $GUID = $Request.Body.GUID

        if ($Action -eq 'delete') {
            if (-not $GUID) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{
                        Results = 'GUID is required for delete action'
                    }
                }
            }

            Remove-AzDataTableEntity @Table -Entity @{
                PartitionKey = 'Preset'
                RowKey       = $GUID
            }

            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    Results = 'Preset deleted successfully'
                }
            }
        } else {
            # Save or update preset
            $Name = $Request.Body.name
            $Query = $Request.Body.query

            if (-not $Name -or -not $Query) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{
                        Results = 'Name and query are required'
                    }
                }
            }

            # Use provided GUID or generate new one
            if (-not $GUID) {
                $GUID = (New-Guid).Guid
            }

            # Convert query to compressed JSON for storage
            $QueryJson = ConvertTo-Json -InputObject @{ query = $Query } -Compress

            $Entity = @{
                PartitionKey = 'Preset'
                RowKey       = [string]$GUID
                name         = [string]$Name
                data         = [string]$QueryJson
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    Results  = 'Preset saved successfully'
                    Metadata = @{
                        GUID = $GUID
                    }
                }
            }
        }
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                Error = "Failed to manage diagnostics preset: $($_.Exception.Message)"
            }
        }
    }
}
