function Register-CIPPExtensionScheduledTasks {
    Param(
        [switch]$Reschedule
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

    $Extensions = @('Hudu')

    foreach ($Extension in $Extensions) {
        $ExtensionConfig = $Config.$Extension
        if ($ExtensionConfig.Enabled -eq $true) {
            $Mappings = Get-CIPPAzDataTableEntity @MappingsTable -Filter "PartitionKey eq '$($Extension)Mapping'"
            $FieldMapping = Get-CIPPAzDataTableEntity @MappingsTable -Filter "PartitionKey eq '$($Extension)FieldMapping'"
            $FieldSync = @{}
            $SyncTypes = [System.Collections.Generic.List[string]]::new()

            foreach ($Mapping in $FieldMapping) {
                $FieldSync[$Mapping.RowKey] = !([string]::IsNullOrEmpty($Mapping.IntegrationId))
            }

            $SyncTypes.Add('Overview')
            $SyncTypes.Add('Groups')

            if ($FieldSync.Users) {
                $SyncTypes.Add('Users')
                $SyncTypes.Add('Mailboxes')
            }
            if ($FieldSync.Devices) {
                $SyncTypes.Add('Devices')
            }

            foreach ($Mapping in $Mappings) {
                $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }

                foreach ($SyncType in $SyncTypes) {
                    $ExistingTask = $ScheduledTasks | Where-Object { $_.Tenant -eq $Tenant.defaultDomainName -and $_.SyncType -eq $SyncType }
                    if (!$ExistingTask -or $Reschedule.IsPresent) {
                        $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
                        $Task = @{
                            Name          = "Extension Sync - $SyncType"
                            Command       = @{
                                value = 'Sync-CippExtensionData'
                                label = 'Sync-CippExtensionData'
                            }
                            Parameters    = @{
                                TenantFilter = $Tenant.defaultDomainName
                                SyncType     = $SyncType
                            }
                            Recurrence    = '1d'
                            ScheduledTime = $unixtime
                            TenantFilter  = $Tenant.defaultDomainName
                        }
                        if ($ExistingTask) {
                            $Task.RowKey = $ExistingTask.RowKey
                        }
                        $null = Add-CIPPScheduledTask -Task $Task -hidden $true -SyncType $SyncType
                    }
                }

                $ExistingTask = $PushTasks | Where-Object { $_.Tenant -eq $Tenant.defaultDomainName -and $_.SyncType -eq $Extension }
                if (!$ExistingTask -or $Reschedule.IsPresent) {
                    # push cached data to extension
                    $in30mins = [int64](([datetime]::UtcNow.AddMinutes(30)) - (Get-Date '1/1/1970')).TotalSeconds
                    $Task = @{
                        Name          = "$Extension Extension Sync"
                        Command       = @{
                            value = 'Push-CippExtensionData'
                            label = 'Push-CippExtensionData'
                        }
                        Parameters    = @{
                            TenantFilter = $Tenant.defaultDomainName
                            Extension    = $Extension
                        }
                        Recurrence    = '1d'
                        ScheduledTime = $in30mins
                        TenantFilter  = $Tenant.defaultDomainName
                    }
                    $null = Add-CIPPScheduledTask -Task $Task -hidden $true -SyncType $Extension
                }
            }
        }
    }

}
