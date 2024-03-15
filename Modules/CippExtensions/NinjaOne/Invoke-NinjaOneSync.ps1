function Invoke-NinjaOneSync {
    try {
        $Table = Get-CIPPTable -TableName NinjaOneSettings

        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
        $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }


        $Batch = foreach ($Tenant in $TenantsToProcess) {
            <#Push-OutputBinding -Name NinjaProcess -Value @{
                'NinjaAction'  = 'SyncTenant'
                'MappedTenant' = $Tenant
            }
            Start-Sleep -Seconds 1#>
            [PSCustomObject]@{
                'NinjaAction'  = 'SyncTenant'
                'MappedTenant' = $Tenant
                'FunctionName' = 'NinjaOneQueue'
            }
        }
        if (($Batch | Measure-Object).Count -gt 0) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'NinjaOneOrchestrator'
                Batch            = @($Batch)
            }
            #Write-Host ($InputObject | ConvertTo-Json)
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
            Write-Host "Started permissions orchestration with ID = '$InstanceId'"
        }

        $AddObject = @{
            PartitionKey   = 'NinjaConfig'
            RowKey         = 'NinjaLastRunTime'
            'SettingValue' = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
        }

        Add-AzDataTableEntity @Table -Entity $AddObject -Force

        Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info'
    } catch {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start NinjaOne Sync $($_.Exception.Message)" -sev Error
    }

}
