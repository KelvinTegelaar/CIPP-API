function Set-CIPPNotificationConfig {
    [CmdletBinding()]
    param (
        $email,
        $webhook,
        $onepertenant,
        $logsToInclude,
        $sendtoIntegration,
        $sev,
        $APIName = 'Set Notification Config'
    )

    $results = try {
        $Table = Get-CIPPTable -TableName SchedulerConfig
        $SchedulerConfig = @{
            'tenant'            = 'Any'
            'tenantid'          = 'TenantId'
            'type'              = 'CIPPNotifications'
            'schedule'          = 'Every 15 minutes'
            'Severity'          = [string]$sev
            'email'             = "$($email)"
            'webhook'           = "$($webhook)"
            'onePerTenant'      = [boolean]$onePerTenant
            'sendtoIntegration' = [boolean]$sendtoIntegration
            'includeTenantId'   = $true
            'PartitionKey'      = 'CippNotifications'
            'RowKey'            = 'CippNotifications'
        }
        foreach ($logvalue in [pscustomobject]$logsToInclude) {
            $SchedulerConfig[([pscustomobject]$logvalue.value)] = $true
        }

        Add-CIPPAzDataTableEntity @Table -Entity $SchedulerConfig -Force | Out-Null
        return 'Successfully set the configuration'
    } catch {
        return "Failed to set configuration: $($_.Exception.message)"
    }
}
