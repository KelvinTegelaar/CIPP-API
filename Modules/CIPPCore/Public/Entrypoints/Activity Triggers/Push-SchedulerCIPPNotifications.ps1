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
        $severity = [System.Collections.ArrayList]@('Info', 'Error', 'Warning', 'Critical', 'Alert')
    }
    Write-Information "Our Severity table is: $severity"

    $Table = Get-CIPPTable
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
    $Currentlog = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object {
        $_.API -in $Settings -and $_.sentAsAlert -ne $true -and $_.Severity -in $severity
    }
    $StandardsTable = Get-CIPPTable -tablename CippStandardsAlerts
    $CurrentStandardsLogs = Get-CIPPAzDataTableEntity @StandardsTable -Filter $Filter | Where-Object {
        $_.sentAsAlert -ne $true
    }
    Write-Information "Alerts: $($Currentlog.count) found"
    Write-Information "Standards: $($CurrentStandardsLogs.count) found"

    # Get the CIPP URL
    $CippConfigTable = Get-CippTable -tablename Config
    $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    $CIPPURL = 'https://{0}' -f $CippConfig.Value

    #email try
    try {
        if ($Config.email -like '*@*') {
            #Normal logs
            if ($Currentlog) {
                if ($config.onePerTenant) {
                    foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                        $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant)
                        $Subject = "$($Tenant): CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                        $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                        Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                        $UpdateLogs = $CurrentLog | ForEach-Object {
                            if ($_.PSObject.Properties.Name -contains 'sentAsAlert') {
                                $_.sentAsAlert = $true
                            } else {
                                $_ | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
                            }
                            $_
                        }
                        if ($UpdateLogs) {
                            Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force
                        }
                    }
                } else {
                    $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity)
                    $Subject = "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                    $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                    Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                    $UpdateLogs = $CurrentLog | ForEach-Object {
                        if ($_.PSObject.Properties.Name -contains 'sentAsAlert') {
                            $_.sentAsAlert = $true
                        } else {
                            $_ | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
                        }
                        $_
                    }
                    if ($UpdateLogs) {
                        Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force
                    }
                }
            }
            if ($CurrentStandardsLogs) {
                foreach ($tenant in ($CurrentStandardsLogs.Tenant | Sort-Object -Unique)) {
                    $Data = ($CurrentStandardsLogs | Where-Object -Property tenant -EQ $tenant)
                    $Subject = "$($Tenant): Standards are out of sync for $tenant"
                    $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'standards' -CIPPURL $CIPPURL
                    Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                    $updateStandards = $CurrentStandardsLogs | ForEach-Object {
                        if ($_.PSObject.Properties.Name -contains 'sentAsAlert') {
                            $_.sentAsAlert = $true
                        } else {
                            $_ | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
                        }
                        $_
                    }
                    if ($updateStandards) { Add-CIPPAzDataTableEntity @StandardsTable -Entity $updateStandards -Force }
                }
            }
        }
    } catch {
        Write-Information "Could not send alerts to email: $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alert emails: $($_.Exception.message)" -sev error -LogData (Get-CippException -Exception $_)
    }

    try {
        Write-Information $($config | ConvertTo-Json)
        Write-Information $config.webhook
        if (![string]::IsNullOrEmpty($config.webhook)) {
            if ($Currentlog) {
                $JSONContent = $Currentlog | ConvertTo-Json -Compress
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
                $UpdateLogs = $CurrentLog | ForEach-Object { $_.sentAsAlert = $true; $_ }
                if ($UpdateLogs) { Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force }
            }

            if ($CurrentStandardsLogs) {
                $Data = $CurrentStandardsLogs
                $JSONContent = New-CIPPAlertTemplate -Data $Data -Format 'json' -InputObject 'table' -CIPPURL $CIPPURL
                $CurrentStandardsLogs | ConvertTo-Json -Compress
                Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
                $updateStandards = $CurrentStandardsLogs | ForEach-Object {
                    if ($_.PSObject.Properties.Name -contains 'sentAsAlert') {
                        $_.sentAsAlert = $true
                    } else {
                        $_ | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
                    }
                    $_
                }
            }

        }
    } catch {
        Write-Information "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)" -tenant $Tenant -sev error -LogData (Get-CippException -Exception $_)
    }

    if ($config.sendtoIntegration) {
        try {
            foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant)
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table' -CIPPURL $CIPPURL
                $Title = "$tenant CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                $UpdateLogs = $CurrentLog | ForEach-Object { $_.SentAsAlert = $true; $_ }
                if ($UpdateLogs) { Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force }
            }
            foreach ($standardsTenant in ($CurrentStandardsLogs.Tenant | Sort-Object -Unique)) {
                $Data = ($CurrentStandardsLogs | Where-Object -Property tenant -EQ $standardsTenant)
                $Subject = "$($standardsTenant): Standards are out of sync for $standardsTenant"
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'standards' -CIPPURL $CIPPURL
                Send-CIPPAlert -Type 'psa' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $standardsTenant -APIName 'Alerts'
                $updateStandards = $CurrentStandardsLogs | ForEach-Object {
                    if ($_.PSObject.Properties.Name -contains 'sentAsAlert') {
                        $_.sentAsAlert = $true
                    } else {
                        $_ | Add-Member -MemberType NoteProperty -Name sentAsAlert -Value $true -Force
                    }
                    $_
                }
            }
        } catch {
            Write-Information "Could not send alerts to ticketing system: $($_.Exception.message)"
            Write-LogMessage -API 'Alerts' -tenant $Tenant -message "Could not send alerts to ticketing system: $($_.Exception.message)" -sev Error
        }
    }

}
