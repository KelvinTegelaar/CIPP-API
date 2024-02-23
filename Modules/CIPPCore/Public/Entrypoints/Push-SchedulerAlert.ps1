function Push-SchedulerAlert {
    param (
        $QueueItem, $TriggerMetadata
    )
    $Tenant = $QueueItem
    try {
        $Table = Get-CIPPTable -Table SchedulerConfig
        if ($Tenant.tag -eq 'AllTenants') {
            $Filter = "RowKey eq 'AllTenants' and PartitionKey eq 'Alert'"
        } else {
            $Filter = "RowKey eq '{0}' and PartitionKey eq 'Alert'" -f $Tenant.tenantid
        }
        $Alerts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    
        $IgnoreList = @('Etag', 'PartitionKey', 'Timestamp', 'RowKey', 'tenantid', 'tenant', 'type')
        $alertList = $Alerts | Select-Object * -ExcludeProperty $IgnoreList 
        foreach ($task in ($AlertList.psobject.members | Where-Object { $_.MemberType -EQ 'NoteProperty' -and $_.value -eq $True }).name) {
            $Table = Get-CIPPTable -TableName AlertRunCheck
            $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}' and Timestamp ge datetime'{2}'" -f $tenant.tenant, $task, (Get-Date).AddMinutes(-10).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
            $ExistingMessage = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if (!$ExistingMessage) {
                $QueueItem = [pscustomobject]@{
                    tenant       = $tenant.tenant
                    tenantid     = $tenant.tenantid
                    FunctionName = "CIPPAlert$($Task)"
                }
                Push-OutputBinding -Name QueueItemOut -Value $QueueItem
                $QueueItem | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value $task -Force
                $QueueItem | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value $tenant.tenant -Force
                Add-CIPPAzDataTableEntity @Table -Entity $QueueItem -Force
            } else {
                Write-Host ('ALERTS: Duplicate run found. Ignoring. Tenant: {0}, Task: {1}' -f $tenant.tenant, $task)
            }

        }
    } catch {
        $Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
        Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
    }
}