function Push-SchedulerAlert {
    param (
        $Item
    )

    try {
        $Table = Get-CIPPTable -Table SchedulerConfig
        if ($Item.Tag -eq 'AllTenants') {
            $Filter = "RowKey eq 'AllTenants' and PartitionKey eq 'Alert'"
        } else {
            $Filter = "RowKey eq '{0}' and PartitionKey eq 'Alert'" -f $Item.Tenantid
        }
        $Alerts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $IgnoreList = @('Etag', 'PartitionKey', 'Timestamp', 'RowKey', 'tenantid', 'tenant', 'type')
        $AlertList = $Alerts | Select-Object * -ExcludeProperty $IgnoreList
        foreach ($task in ($AlertList.psobject.members | Where-Object { $_.MemberType -EQ 'NoteProperty' -and $_.value -ne $false })) {
            $Table = Get-CIPPTable -TableName AlertRunCheck
            $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}' and Timestamp ge datetime'{2}'" -f $Item.Tenant, $task.Name, (Get-Date).AddMinutes(-10).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
            $ExistingMessage = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if (!$ExistingMessage) {
                $Item = [pscustomobject]@{
                    Tenant   = $Item.Tenant
                    Tenantid = $Item.Tenantid
                    value    = $Task.value
                }
                $Function = "Push-CIPPAlert$($Task.Name)"
                & $Function -Item $Item
                #Push-OutputBinding -Name QueueItemOut -Value $Item
                $Item | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value $task.Name -Force
                $Item | Add-Member -MemberType NoteProperty -Name 'PartitionKey' -Value $Item.Tenant -Force

                if ($null -eq $Item.Tenant) {
                    Write-Host ($Item | ConvertTo-Json)
                } else {
                    try {
                        $null = Add-CIPPAzDataTableEntity @Table -Entity $Item -Force -ErrorAction Stop
                    } catch {
                        Write-Host "################### Error updating alert $($_.Exception.Message) - Task:$($Task.Name) PK:$($Item.PartitionKey)"
                    }
                }
            } else {
                Write-Host ('ALERTS: Duplicate run found. Ignoring. Tenant: {0}, Task: {1}' -f $Item.Tenant, $task.Name)
            }
        }
        <#if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AlertsOrchestrator'
                SkipLog          = $true
                Batch            = @($Batch)
            }
            #Write-Host ($Batch | ConvertTo-Json)
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
            Write-Host "Started alert orchestration with ID = '$InstanceId'"
            #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
        } else {
            Write-Host 'No alerts to process'
        }#>
    } catch {
        $Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
        Write-LogMessage -message $Message -API 'Alerts' -tenant $Item.tenant -sev Error
    }
}