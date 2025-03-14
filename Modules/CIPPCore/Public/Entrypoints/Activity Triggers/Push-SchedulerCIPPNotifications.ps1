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
        $_.API -In $Settings -and $_.SentAsAlert -ne $true -and $_.Severity -In $severity
    }
    Write-Information "Alerts: $($Currentlog.count) found"
    #email try
    try {
        if ($Config.email -like '*@*' -and $null -ne $CurrentLog) {
            if ($config.onePerTenant) {
                foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                    $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant)
                    $Subject = "$($Tenant): CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                    $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table'
                    Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
                }
            } else {
                $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | ConvertTo-Html -frag)
                $Subject = "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table'
                Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'
            }
        }
    } catch {
        Write-Information "Could not send alerts to email: $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alert emails: $($_.Exception.message)" -sev error -LogData (Get-CippException -Exception $_)
    }

    try {
        Write-Information $($config | ConvertTo-Json)
        Write-Information $config.webhook
        if ($Config.webhook -ne '' -and $null -ne $CurrentLog) {
            $JSONContent = $Currentlog | ConvertTo-Json -Compress
            Send-CIPPAlert -Type 'webhook' -JSONContent $JSONContent -TenantFilter $Tenant -APIName 'Alerts'
        }

        $UpdateLogs = $CurrentLog | ForEach-Object {
            $_.SentAsAlert = $true
            $_
        }
        if ($UpdateLogs) {
            Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force
        }
    } catch {
        Write-Information "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alerts to webhook $($config.webhook): $($_.Exception.message)" -tenant $Tenant -sev error -LogData (Get-CippException -Exception $_)
    }

    if ($config.sendtoIntegration) {
        try {
            foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                $Data = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant | ConvertTo-Html -frag)
                $HTMLContent = New-CIPPAlertTemplate -Data $Data -Format 'html' -InputObject 'table'
                $Title = "$tenant CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $HTMLContent.htmlcontent -TenantFilter $tenant -APIName 'Alerts'

                $UpdateLogs = $CurrentLog | ForEach-Object {
                    $_.SentAsAlert = $true
                    $_
                }
                if ($UpdateLogs) {
                    Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force
                }
            }
        } catch {
            Write-Information "Could not send alerts to ticketing system: $($_.Exception.message)"
            Write-LogMessage -API 'Alerts' -tenant $Tenant -message "Could not send alerts to ticketing system: $($_.Exception.message)" -sev Error
        }
    }


}
