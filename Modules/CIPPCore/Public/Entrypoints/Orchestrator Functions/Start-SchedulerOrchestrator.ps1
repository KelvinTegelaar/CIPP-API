function Start-SchedulerOrchestrator {
    <#
    .SYNOPSIS
    Start the Scheduler Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Tenants = Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -NE 'WebhookAlert'

    $ValidTypes = @('CIPPNotifications', 'webhookcreation')

    $Tasks = foreach ($Tenant in $Tenants) {
        if ($Tenant.type -notin $ValidTypes) {
            if ($Tenant.PartitionKey -eq 'Alert') {
                Write-Information "Scheduler: removing legacy classic-alert row for '$($Tenant.tenant)'"
                Remove-CIPPAzDataTableEntity -Force @Table -Entity $Tenant
            } else {
                Write-Information "Scheduler: skipping row $($Tenant.PartitionKey)/$($Tenant.RowKey) - no handler for type '$($Tenant.type)'"
            }
            continue
        }
        if ($Tenant.tenant -ne 'AllTenants') {
            [pscustomobject]@{
                Tenant   = $Tenant.tenant
                Tag      = 'SingleTenant'
                TenantID = $Tenant.tenantid
                Type     = $Tenant.type
                RowKey   = $Tenant.RowKey
            }
        } else {
            Write-Information 'All tenants, doing them all'
            $TenantList = Get-Tenants
            foreach ($t in $TenantList) {
                [pscustomobject]@{
                    Tenant   = $t.defaultDomainName
                    Tag      = 'AllTenants'
                    TenantID = $t.customerId
                    Type     = $Tenant.type
                    RowKey   = $Tenant.RowKey
                }
            }
        }
    }

    if (($Tasks | Measure-Object).Count -eq 0) {
        return
    }

    $Queue = New-CippQueueEntry -Name 'Scheduler' -TotalTasks ($Tasks | Measure-Object).Count

    $Batch = foreach ($Task in $Tasks) {
        [pscustomobject]@{
            Tenant       = $task.tenant
            Tenantid     = $task.tenantid
            Tag          = $task.tag
            Type         = $task.type
            QueueId      = $Queue.RowKey
            SchedulerRow = $Task.RowKey
            QueueName    = '{0} - {1}' -f $Task.Type, $task.tenant
            FunctionName = "Scheduler$($Task.Type)"
        }
    }
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'SchedulerOrchestrator'
        Batch            = @($Batch)
        SkipLog          = $true
    }

    if ($PSCmdlet.ShouldProcess('Start-ScheduleOrchestrator', 'Starting Scheduler Orchestrator')) {
        Start-CIPPOrchestrator -InputObject $InputObject
    }
}
