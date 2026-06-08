function Push-SchedulerCIPPNotifications {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $QueueItem, $TriggerMetadata
    )
    #Add new alert engine.
    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
    $Config = [pscustomobject](Get-CIPPAzDataTableEntity @Table -Filter $Filter)

    $Settings = [System.Collections.Generic.List[string]]@('Alerts')
    $Config.psobject.properties.name | ForEach-Object { if ($Config.$_ -eq $true) { $Settings.Add($_) } }
    Write-Information "Our APIs are: $($Settings -join ',')"

    $severity = $Config.Severity -split ','
    if (!$severity) {
        $severity = @('Info', 'Error', 'Warning', 'Critical', 'Alert')
    }
    Write-Information "Our Severity table is: $severity"

    $LogTable = Get-CIPPTable
    $StandardsTable = Get-CIPPTable -tablename CippStandardsAlerts
    $PartitionKey = Get-Date -UFormat '%Y%m%d'

    # Server-side: sentAsAlert + severity (small fixed set). API is filtered client-side
    # because the API list is open-ended and OR-expanding it can exceed the OData filter limit.
    $sevOr = ($severity | ForEach-Object { "Severity eq '$($_ -replace "'", "''")'" }) -join ' or '
    $LogFilter = "PartitionKey eq '$PartitionKey' and sentAsAlert eq false and ($sevOr)"
    $StandardsFilter = "PartitionKey eq '$PartitionKey' and sentAsAlert eq false"

    $Currentlog = @(Get-CIPPAzDataTableEntity @LogTable -Filter $LogFilter | Where-Object { $_.API -in $Settings })
    $CurrentStandardsLogs = @(Get-CIPPAzDataTableEntity @StandardsTable -Filter $StandardsFilter)

    Write-Information "Alerts: $($Currentlog.Count) found"
    Write-Information "Standards: $($CurrentStandardsLogs.Count) found"

    # Get the CIPP URL
    $CippConfigTable = Get-CippTable -tablename Config
    $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    $CIPPURL = 'https://{0}' -f $CippConfig.Value

    $LogsByTenant = @($Currentlog | Group-Object -Property Tenant)
    $StandardsByTenant = @($CurrentStandardsLogs | Group-Object -Property Tenant)

    $MarkSent = {
        param($Entities, $TargetTable)
        if (-not $Entities -or $Entities.Count -eq 0) { return }
        $batch = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $Entities) {
            if ($e.PSObject.Properties.Name -contains 'sentAsAlert') {
                $e.sentAsAlert = $true
            } else {
                $e | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
            }
            $batch.Add($e)
            if ($batch.Count -ge 100) {
                Add-CIPPAzDataTableEntity @TargetTable -Entity $batch -Force
                $batch.Clear()
            }
        }
        if ($batch.Count -gt 0) {
            Add-CIPPAzDataTableEntity @TargetTable -Entity $batch -Force
        }
    }

    try {
        if ($Config.email -like '*@*') {
            if ($Currentlog.Count -gt 0) {
                if ($config.onePerTenant) {
                    foreach ($g in $LogsByTenant) {
                        $tenant = $g.Name
                        $Data = $g.Group | Select-Object Message, API, Tenant, Username, Severity
                        $Subject = "$($tenant): CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                        $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                        Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                        & $MarkSent $g.Group $LogTable
                        $Data = $null; $HTMLContent = $null
                    }
                } else {
                    $Data = $CurrentLog | Select-Object Message, API, Tenant, Username, Severity
                    $Subject = "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                    $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                    Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter 'AllTenants' -APIName 'Alerts'
                    & $MarkSent $CurrentLog $LogTable
                    $Data = $null; $HTMLContent = $null
                }
            }
            if ($CurrentStandardsLogs.Count -gt 0) {
                foreach ($g in $StandardsByTenant) {
                    $tenant = $g.Name
                    $Data = $g.Group
                    $Subject = "$($tenant): Standards are out of sync for $tenant"
                    $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'standards' -CIPPURL $CIPPURL
                    Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                    & $MarkSent $g.Group $StandardsTable
                    $Data = $null; $HTMLContent = $null
                }
            }
        }
    } catch {
        Write-Information "Could not send alerts to email: $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alert emails: $($_.Exception.message)" -sev error -LogData (Get-CippException -Exception $_)
    }

    try {
        Write-Information $config.webhook
        if (![string]::IsNullOrEmpty($config.webhook)) {
            $ChunkSize = 500
            if ($Currentlog.Count -gt 0) {
                $Title = "Logbook Notification: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                for ($i = 0; $i -lt $Currentlog.Count; $i += $ChunkSize) {
                    $end = [math]::Min($i + $ChunkSize - 1, $Currentlog.Count - 1)
                    $chunk = $Currentlog[$i..$end]
                    $JSONContent = $chunk | ConvertTo-Json -Compress
                    Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $JSONContent -TenantFilter 'AllTenants' -APIName 'Alerts' -SchemaSource 'Logbook Notification' -InvokingCommand 'Push-SchedulerCIPPNotifications' -UseStandardizedSchema:$([boolean]$Config.UseStandardizedSchema)
                    & $MarkSent $chunk $LogTable
                    $JSONContent = $null; $chunk = $null
                }
            }

            if ($CurrentStandardsLogs.Count -gt 0) {
                $Title = 'Standards Notification: Out of sync standards detected'
                for ($i = 0; $i -lt $CurrentStandardsLogs.Count; $i += $ChunkSize) {
                    $end = [math]::Min($i + $ChunkSize - 1, $CurrentStandardsLogs.Count - 1)
                    $chunk = $CurrentStandardsLogs[$i..$end]
                    $JSONContent = New-CIPPAlertTemplate -Data $chunk -Format 'json' -InputObject 'table' -CIPPURL $CIPPURL
                    Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $JSONContent -TenantFilter 'AllTenants' -APIName 'Alerts' -SchemaSource 'Standards Notification' -InvokingCommand 'Push-SchedulerCIPPNotifications' -UseStandardizedSchema:$([boolean]$Config.UseStandardizedSchema)
                    & $MarkSent $chunk $StandardsTable
                    $JSONContent = $null; $chunk = $null
                }
            }
        }
    } catch {
        Write-Information "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)" -tenant 'AllTenants' -sev error -LogData (Get-CippException -Exception $_)
    }

    if ($config.sendtoIntegration) {
        try {
            foreach ($g in $LogsByTenant) {
                $tenant = $g.Name
                $Data = $g.Group | Select-Object Message, API, Tenant, Username, Severity
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                $Title = "$tenant CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                & $MarkSent $g.Group $LogTable
                $Data = $null; $HTMLContent = $null
            }
            foreach ($g in $StandardsByTenant) {
                $tenant = $g.Name
                $Data = $g.Group
                $Subject = "$($tenant): Standards are out of sync for $tenant"
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'standards' -CIPPURL $CIPPURL
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                & $MarkSent $g.Group $StandardsTable
                $Data = $null; $HTMLContent = $null
            }
        } catch {
            Write-Information "Could not send alerts to ticketing system: $($_.Exception.message)"
            Write-LogMessage -API 'Alerts' -tenant 'AllTenants' -message "Could not send alerts to ticketing system: $($_.Exception.message)" -sev Error
        }
    }
}
