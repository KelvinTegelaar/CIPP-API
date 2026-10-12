function Invoke-ExecLogRetentionConfig {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Config
    $Filter = "PartitionKey eq 'LogRetention' and RowKey eq 'Settings'"

    if (-not $Request.Query.List) {
        $RetentionDays = $Request.Body.RetentionDays -as [int]
        $ValidationError = if ($RetentionDays -lt 7) {
            'Retention days must be at least 7 days'
        } elseif ($RetentionDays -gt 365) {
            'Retention days must be at most 365 days'
        }
        if ($ValidationError) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = [pscustomobject]@{'Results' = "Failed to set configuration: $ValidationError" }
                })
        }
    }

    $StatusCode = [HttpStatusCode]::OK
    $results = try {
        if ($Request.Query.List) {
            $RetentionSettings = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if (!$RetentionSettings) {
                # Return default values if not set
                @{
                    RetentionDays = 90
                }
            } else {
                @{
                    RetentionDays = [int]$RetentionSettings.RetentionDays
                }
            }
        } else {
            $RetentionConfig = @{
                'RetentionDays' = $RetentionDays
                'PartitionKey'  = 'LogRetention'
                'RowKey'        = 'Settings'
            }

            Add-CIPPAzDataTableEntity @Table -Entity $RetentionConfig -Force | Out-Null
            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Set log retention to $RetentionDays days" -Sev 'Info'
            "Successfully set log retention to $RetentionDays days"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to set log retention configuration: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        "Failed to set configuration: $($ErrorMessage.NormalizedError)"
    }

    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
