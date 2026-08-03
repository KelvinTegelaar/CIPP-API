function Invoke-ExecSetCIPPAutoBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Backup.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $StatusCode = [HttpStatusCode]::OK

    try {
        $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        if ($Request.Body.Enabled -eq $true) {
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $AutomatedCIPPBackupTask = Get-AzDataTableEntity @table -Filter "Name eq 'Automated CIPP Backup'" -Property RowKey, PartitionKey, ETag
            if ($AutomatedCIPPBackupTask) {
                Remove-CIPPAzDataTableEntity -Force @Table -Entity $AutomatedCIPPBackupTask | Out-Null
            }

            $TaskBody = [pscustomobject]@{
                TenantFilter  = 'PartnerTenant'
                Name          = 'Automated CIPP Backup'
                Command       = @{
                    value = 'New-CIPPBackup'
                    label = 'New-CIPPBackup'
                }
                Parameters    = [pscustomobject]@{ backupType = 'CIPP' }
                ScheduledTime = $unixtime
                Recurrence    = '1d'
            }
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false -DisallowDuplicateName $true
            $Result = @{ 'Results' = 'Scheduled Task Successfully created' } | ConvertTo-Json -Compress
            Write-LogMessage -headers $Request.Headers -API $APIName -message 'Scheduled automatic CIPP backups' -Sev 'Info'
        } elseif ($Request.Body.Enabled -eq $false) {
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $AutomatedCIPPBackupTask = Get-AzDataTableEntity @table -Filter "Name eq 'Automated CIPP Backup'" -Property RowKey, PartitionKey, ETag
            if ($AutomatedCIPPBackupTask) {
                Remove-CIPPAzDataTableEntity -Force @Table -Entity $AutomatedCIPPBackupTask | Out-Null
                $Result = @{ 'Results' = 'Scheduled Task Successfully removed' } | ConvertTo-Json -Compress
            } else {
                $Result = @{ 'Results' = 'No existing scheduled task found to remove' } | ConvertTo-Json -Compress
            }
        } else {
            $Result = @{ 'Results' = 'No action taken - Enabled parameter not set' } | ConvertTo-Json -Compress
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to schedule automatic CIPP backups: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = @{
            error   = "Failed to schedule automatic backups: $($ErrorMessage.NormalizedError)"
            details = @{
                operation      = 'SetAutoBackup'
                innerException = $_.Exception.Message
            }
        } | ConvertTo-Json -Depth 5 -Compress
    }

    return ([HttpResponseContext]@{
            StatusCode  = $StatusCode
            ContentType = 'application/json'
            Body        = $Result
        })

}
