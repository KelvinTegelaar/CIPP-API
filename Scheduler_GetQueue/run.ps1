param($Timer)

$Table = Get-CIPPTable -TableName SchedulerConfig
$Tenants = Get-CIPPAzDataTableEntity @Table | Where-Object -Property PartitionKey -NE 'WebhookAlert'

$Tasks = foreach ($Tenant in $Tenants) {
    if ($Tenant.tenant -ne 'AllTenants') {
        [pscustomobject]@{ 
            Tenant   = $Tenant.tenant
            Tag      = 'SingleTenant'
            TenantID = $Tenant.tenantid
            Type     = $Tenant.type
        }
    } else {
        Write-Host 'All tenants, doing them all'
        $TenantList = Get-Tenants
        foreach ($t in $TenantList) {
            [pscustomobject]@{ 
                Tenant   = $t.defaultDomainName
                Tag      = 'AllTenants'
                TenantID = $t.customerId
                Type     = $Tenant.type
            }
        }
    }
}   

foreach ($Task in $Tasks) {
    $QueueItem = [pscustomobject]@{
        Tenant       = $task.tenant
        Tenantid     = $task.tenantid
        Tag          = $task.tag
        Type         = $task.type
        FunctionName = "Scheduler$($Task.Type)"
    }
    try {
        Push-OutputBinding -Name QueueItem -Value $QueueItem 
    } catch {
        Write-Host "Could not launch queue item for $($Task.tenant): $($_.Exception.Message)"
    }
}