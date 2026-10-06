function Invoke-NinjaOneSync {
    try {
        $Table = Get-CIPPTable -TableName NinjaOneSettings

        $CIPPMapping = Get-CIPPTable -TableName CippMapping
        $Filter = "PartitionKey eq 'NinjaOneMapping'"
        $TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.IntegrationId -and $_.IntegrationId -ne '' }

        # Same check as the integration test button, once, before queuing a task per mapped tenant.
        $ExtTable = Get-CIPPTable -TableName Extensionsconfig
        $NinjaConfig = ((Get-AzDataTableEntity @ExtTable).config | ConvertFrom-Json).NinjaOne
        if ($TenantsToProcess -and -not (Get-NinjaOneToken -configuration $NinjaConfig).access_token) {
            throw "NinjaOne API check failed, synchronization not queued for $(($TenantsToProcess | Measure-Object).count) tenants. Test the NinjaOne integration in Extensions."
        }


        $TenantDomains = @{}
        foreach ($T in Get-Tenants -IncludeErrors) { $TenantDomains[$T.customerId] = $T.defaultDomainName }
        $Batch = foreach ($Tenant in $TenantsToProcess) {
            [PSCustomObject]@{
                'TenantFilter' = $TenantDomains[$Tenant.RowKey] ?? $Tenant.RowKey
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
            $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
            Write-Host "Started permissions orchestration with ID = '$InstanceId'"
        }

        $AddObject = @{
            PartitionKey   = 'NinjaConfig'
            RowKey         = 'NinjaLastRunTime'
            'SettingValue' = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
        }

        Add-AzDataTableEntity @Table -Entity $AddObject -Force

        Write-LogMessage -API 'NinjaOneAutoMap_Queue' -Headers 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info'
    } catch {
        Write-LogMessage -API 'Scheduler_Billing' -tenant 'none' -message "Could not start NinjaOne Sync $($_.Exception.Message)" -sev Error
    }

}
