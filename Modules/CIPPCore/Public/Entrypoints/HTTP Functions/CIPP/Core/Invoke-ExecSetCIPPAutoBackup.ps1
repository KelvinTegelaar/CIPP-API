function Invoke-ExecSetCIPPAutoBackup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Backup.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    if ($Request.Body.Enabled -eq $true) {
        $Table = Get-CIPPTable -TableName 'ScheduledTasks'
        $AutomatedCIPPBackupTask = Get-AzDataTableEntity @table -Filter "Name eq 'Automated CIPP Backup'"
        $task = @{
            RowKey       = $AutomatedCIPPBackupTask.RowKey
            PartitionKey = 'ScheduledTask'
        }
        Remove-AzDataTableEntity -Force @Table -Entity $task | Out-Null

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
        $Result = @{ 'Results' = 'Scheduled Task Successfully created' }
    } elseif ($Request.Body.Enabled -eq $false) {
        $Table = Get-CIPPTable -TableName 'ScheduledTasks'
        $AutomatedCIPPBackupTask = Get-AzDataTableEntity @table -Filter "Name eq 'Automated CIPP Backup'" -Property RowKey, PartitionKey, ETag
        if ($AutomatedCIPPBackupTask) {
            Remove-AzDataTableEntity -Force @Table -Entity $AutomatedCIPPBackupTask | Out-Null
            $Result = @{ 'Results' = 'Scheduled Task Successfully removed' }
        } else {
            $Result = @{ 'Results' = 'No existing scheduled task found to remove' }
        }

    }
    Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message 'Scheduled automatic CIPP backups' -Sev 'Info'
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Result
        })

}
