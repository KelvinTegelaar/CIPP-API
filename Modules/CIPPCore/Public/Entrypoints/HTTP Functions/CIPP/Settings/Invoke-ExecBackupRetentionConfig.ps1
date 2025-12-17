function Invoke-ExecBackupRetentionConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Config
    $Filter = "PartitionKey eq 'BackupRetention' and RowKey eq 'Settings'"

    $results = try {
        if ($Request.Query.List) {
            $RetentionSettings = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if (!$RetentionSettings) {
                # Return default values if not set
                @{
                    RetentionDays = 30
                }
            } else {
                @{
                    RetentionDays = [int]$RetentionSettings.RetentionDays
                }
            }
        } else {
            $RetentionDays = [int]$Request.Body.RetentionDays

            # Validate minimum value
            if ($RetentionDays -lt 7) {
                throw 'Retention days must be at least 7 days'
            }

            $RetentionConfig = @{
                'RetentionDays' = $RetentionDays
                'PartitionKey'  = 'BackupRetention'
                'RowKey'        = 'Settings'
            }

            Add-CIPPAzDataTableEntity @Table -Entity $RetentionConfig -Force | Out-Null
            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Set backup retention to $RetentionDays days" -Sev 'Info'
            "Successfully set backup retention to $RetentionDays days"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to set backup retention configuration: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        "Failed to set configuration: $($ErrorMessage.NormalizedError)"
    }

    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
