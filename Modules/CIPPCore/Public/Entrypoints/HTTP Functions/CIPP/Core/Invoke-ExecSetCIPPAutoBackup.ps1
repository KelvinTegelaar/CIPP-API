using namespace System.Net

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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
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
            ScheduledTime = $UnixTime
            Recurrence    = '1d'
        }
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false
        $Result = 'Scheduled Task Successfully created'
    }
    Write-LogMessage -headers $Headers -API $APIName -message 'Scheduled automatic CIPP backups' -Sev 'Info'

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ 'Results' = $Result }
    }

}
