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

$Batch = foreach ($Task in $Tasks) {
    [pscustomobject]@{
        Tenant       = $task.tenant
        Tenantid     = $task.tenantid
        Tag          = $task.tag
        Type         = $task.type
        FunctionName = "Scheduler$($Task.Type)"
    }
}
$InputObject = [PSCustomObject]@{
    OrchestratorName = 'SchedulerOrchestrator'
    Batch            = @($Batch)
}
#Write-Host ($InputObject | ConvertTo-Json)
$InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
Write-Host "Started orchestration with ID = '$InstanceId'"
#$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId