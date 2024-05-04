function Push-SchedulerCIPPNotifications {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $QueueItem, $TriggerMetadata
    )

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
        if ($Config.email -like '*@*') {
            $Addresses = $Config.email.split(',').trim()
            $Recipients = foreach ($Address in $Addresses) {
                [PSCustomObject]@{
                    EmailAddress = @{
                        Address = $Address
                    }
                }
            }

            $LogEmails = if ($config.onePerTenant) {
                if ($Config.email -like '*@*' -and $null -ne $CurrentLog) {
                    foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                        $HTMLLog = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant | ConvertTo-Html -frag) -replace '<table>', '<table class=blueTable>' | Out-String
                        $Subject = "$($Tenant): CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                        [PSCustomObject]@{
                            HTMLLog = $HTMLLog
                            Subject = $Subject
                        }
                    }
                }

            } else {
                if ($null -ne $CurrentLog) {
                    $HTMLLog = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | ConvertTo-Html -frag) -replace '<table>', '<table class=blueTable>' | Out-String
                    $Subject = "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                    [PSCustomObject]@{
                        HTMLLog = $HTMLLog
                        Subject = $Subject
                    }
                }
            }

            foreach ($LogEmail in $LogEmails) {
                $Email = [PSCustomObject]@{
                    message         = @{
                        subject      = $LogEmail.Subject
                        body         = @{
                            contentType = 'HTML'
                            content     = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log:<br><br><style>table.blueTable { border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>$($LogEmail.HTMLLog)"
                        }
                        toRecipients = @($Recipients)
                    }
                    saveToSentItems = $false
                }
                $JSONBody = ConvertTo-Json -Depth 10 -Compress -InputObject $Email
                New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/me/sendMail' -tenantid $env:TenantID -type POST -body $JSONBody
            }
            Write-LogMessage -API 'Alerts' -message "Sent $(($LogEmails|Measure-Object).Count) alerts to: $($Addresses -join ', ')" -sev Debug
        }
    } catch {
        Write-Information "Could not send alerts to email: $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alert emails: $($_.Exception.message)" -sev error -LogData (Get-CippException -Exception $_)
    }

    try {
        Write-Information $($config | ConvertTo-Json)
        Write-Information $config.webhook
        if ($Config.webhook -ne '' -and $null -ne $CurrentLog) {
            switch -wildcard ($config.webhook) {

                '*webhook.office.com*' {
                    $Log = $Currentlog | ConvertTo-Html -frag | Out-String
                    $JSonBody = "{`"text`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. <br><br>$Log`"}"
                    Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                }

                '*slack.com*' {
                    $Log = $Currentlog | ForEach-Object {
                        $JSonBody = @"
        {"blocks":[{"type":"header","text":{"type":"plain_text","text":"New Alert from CIPP","emoji":true}},{"type":"section","fields":[{"type":"mrkdwn","text":"*DateTime:*\n$($_.Timestamp)"},{"type":"mrkdwn","text":"*Tenant:*\n$($_.Tenant)"},{"type":"mrkdwn","text":"*API:*\n$($_.API)"},{"type":"mrkdwn","text":"*User:*\n$($_.Username)."}]},{"type":"section","text":{"type":"mrkdwn","text":"*Message:*\n$($_.Message)"}}]}
"@
                        Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                    }
                }

                '*discord.com*' {
                    $Log = $Currentlog | ConvertTo-Html -frag | Out-String
                    $JSonBody = "{`"content`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. $Log`"}"
                    Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                }
                default {
                    $Log = $Currentlog | ConvertTo-Json -Compress
                    $JSonBody = $Log
                    Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                }
            }
            Write-LogMessage -API 'Alerts' -tenant $Tenant -message "Sent Webhook to $($config.webhook)" -sev Debug
        }

        $UpdateLogs = $CurrentLog | ForEach-Object {
            $_.SentAsAlert = $true
            $_
        }
        if ($UpdateLogs) {
            Add-CIPPAzDataTableEntity @Table -Entity $UpdateLogs -Force
        }
    } catch {
        Write-Information "Could not send alerts to webhook: $($_.Exception.message)"
        Write-LogMessage -API 'Alerts' -message "Could not send alerts to : $($_.Exception.message)" -tenant $Tenant -sev error
    }

    if ($config.sendtoIntegration) {
        try {
            foreach ($tenant in ($CurrentLog.Tenant | Sort-Object -Unique)) {
                $HTMLLog = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant | ConvertTo-Html -frag) -replace '<table>', '<table class=blueTable>' | Out-String
                $Alert = @{
                    TenantId   = $Tenant
                    AlertText  = "<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style> $($htmllog)"
                    AlertTitle = "$tenant CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
                }
                New-CippExtAlert -Alert $Alert
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