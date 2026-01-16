function Register-CIPPExtensionScheduledTasks {
    param(
        [switch]$Reschedule,
        [int64]$NextSync = (([datetime]::UtcNow.AddMinutes(30)) - (Get-Date '1/1/1970')).TotalSeconds,
        [string[]]$Extensions = @('Hudu', 'NinjaOne', 'CustomData')
    )

    # get extension configuration and mappings table
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop)
    $MappingsTable = Get-CIPPTable -TableName CippMapping

    # Get existing scheduled usertasks
    $ScheduledTasksTable = Get-CIPPTable -TableName ScheduledTasks
    $ScheduledTasks = Get-CIPPAzDataTableEntity @ScheduledTasksTable -Filter 'Hidden eq true' | Where-Object { $_.Command -match 'Sync-CippExtensionData' }
    $PushTasks = Get-CIPPAzDataTableEntity @ScheduledTasksTable -Filter 'Hidden eq true' | Where-Object { $_.Command -match 'Push-CippExtensionData' }
    $Tenants = Get-Tenants -IncludeErrors

    # Remove all legacy Sync-CippExtensionData tasks (now deprecated - extensions use CippReportingDB)
    Write-Information "Removing $($ScheduledTasks.Count) legacy Sync-CippExtensionData scheduled tasks"
    foreach ($Task in $ScheduledTasks) {
        Write-Information "Removing legacy task: $($Task.Name) for tenant $($Task.Tenant)"
        $Entity = $Task | Select-Object -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @ScheduledTasksTable -Entity $Entity
    }
    $ScheduledTasks = @() # Clear the list since we removed them all

    $MappedTenants = [System.Collections.Generic.List[string]]::new()
    foreach ($Extension in $Extensions) {
        $ExtensionConfig = $Config.$Extension
        if ($ExtensionConfig.Enabled -eq $true -or $Extension -eq 'CustomData') {
            if ($Extension -eq 'CustomData') {
                $CustomDataMappingTable = Get-CIPPTable -TableName CustomDataMappings
                $Mappings = Get-CIPPAzDataTableEntity @CustomDataMappingTable | ForEach-Object {
                    $Mapping = $_.JSON | ConvertFrom-Json
                    if ($Mapping.sourceType.value -eq 'reportingDb' -or $Mapping.sourceType.value -eq 'extensionSync') {
                        $TenantMappings = if ($Mapping.tenantFilter.value -contains 'AllTenants') {
                            $Tenants
                        } else {
                            foreach ($TenantMapping in $TenantMappings) {
                                $TenantMapping | Where-Object { $_.customerId -eq $Mapping.tenantFilter.value -or $_.defaultDomainName -eq $Mapping.tenantFilter.value }
                            }
                        }
                        foreach ($TenantMapping in $TenantMappings) {
                            [pscustomobject]@{
                                RowKey = $TenantMapping.customerId
                            }
                        }
                    }
                } | Sort-Object -Property RowKey -Unique

                if (($Mappings | Measure-Object).Count -eq 0) {
                    Write-Warning 'No tenants found for CustomData extension'
                    continue
                }
            } else {
                $Mappings = Get-CIPPAzDataTableEntity @MappingsTable -Filter "PartitionKey eq '$($Extension)Mapping'"
                $FieldMapping = Get-CIPPAzDataTableEntity @MappingsTable -Filter "PartitionKey eq '$($Extension)FieldMapping'"
            }
            $FieldSync = @{}
            $SyncTypes = [System.Collections.Generic.List[string]]::new()

            foreach ($Mapping in $FieldMapping) {
                $FieldSync[$Mapping.RowKey] = !([string]::IsNullOrEmpty($Mapping.IntegrationId))
            }

            $SyncTypes.Add('Overview')
            $SyncTypes.Add('Groups')
            $SyncTypes.Add('Users')
            $SyncTypes.Add('Mailboxes')
            $SyncTypes.Add('Devices')

            foreach ($Mapping in $Mappings) {
                $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }
                if (!$Tenant) {
                    Write-Warning "Tenant $($Mapping.RowKey) not found"
                    continue
                }
                $MappedTenants.Add($Tenant.defaultDomainName)
                
                # Legacy Sync-CippExtensionData tasks are no longer needed - extensions now use CippReportingDB
                # All cache data is now collected by Push-CIPPDBCacheData scheduled tasks

                $ExistingPushTask = $PushTasks | Where-Object { $_.Tenant -eq $Tenant.defaultDomainName -and $_.SyncType -eq $Extension }
                if ((!$ExistingPushTask -or $Reschedule.IsPresent) -and $Extension -ne 'NinjaOne') {
                    # push cached data to extension

                    $Task = [pscustomobject]@{
                        Name          = "$Extension Extension Sync"
                        Command       = @{
                            value = 'Push-CippExtensionData'
                            label = 'Push-CippExtensionData'
                        }
                        Parameters    = [pscustomobject]@{
                            TenantFilter = $Tenant.defaultDomainName
                            Extension    = $Extension
                        }
                        Recurrence    = '1d'
                        ScheduledTime = $NextSync
                        TenantFilter  = $Tenant.defaultDomainName
                    }
                    if ($ExistingPushTask) {
                        $task | Add-Member -NotePropertyName 'RowKey' -NotePropertyValue $ExistingPushTask.RowKey -Force
                    }
                    $null = Add-CIPPScheduledTask -Task $Task -hidden $true -SyncType $Extension
                    Write-Information "Creating $Extension task for tenant $($Tenant.defaultDomainName)"
                }
            }
        } else {
            # remove existing scheduled tasks
            $PushTasks | Where-Object { $_.SyncType -eq $Extension } | ForEach-Object {
                Write-Information "Extension Disabled: Cleaning up scheduled task $($_.Name) for tenant $($_.Tenant)"
                $Entity = $_ | Select-Object -Property PartitionKey, RowKey
                Remove-AzDataTableEntity -Force @ScheduledTasksTable -Entity $Entity
            }
        }
    }
    $MappedTenants = $MappedTenants | Sort-Object -Unique

    foreach ($Task in $ScheduledTasks) {
        if ($Task.Tenant -notin $MappedTenants) {
            Write-Information "Tenant Removed: Cleaning up scheduled task $($Task.Name) for tenant $($Task.TenantFilter)"
            $Entity = $Task | Select-Object -Property PartitionKey, RowKey
            Remove-AzDataTableEntity -Force @ScheduledTasksTable -Entity $Entity
        }
    }
    foreach ($Task in $PushTasks) {
        if ($Task.Tenant -notin $MappedTenants) {
            Write-Information "Tenant Removed: Cleaning up scheduled task $($Task.Name) for tenant $($Task.TenantFilter)"
            $Entity = $Task | Select-Object -Property PartitionKey, RowKey
            Remove-AzDataTableEntity -Force @ScheduledTasksTable -Entity $Entity
        }
    }
}
