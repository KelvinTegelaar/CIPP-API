
function Send-CIPPAlert {
    [CmdletBinding()]
    param (
        $Type,
        $Title,
        $HTMLContent,
        $JSONContent,
        $TenantFilter,
        $APIName = "Send Alert",
        $ExecutingUser
    )
    Write-Host "Shipping Alert"
    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
    $Config = [pscustomobject](Get-AzDataTableEntity @Table -Filter $Filter)
    if ($Type -eq 'email') {
        Write-Host "Trying to send email"
        try {
            if ($Config.email -like '*@*') {
                $Recipients = $Config.email.split(",").trim() | ForEach-Object { if ($_ -like '*@*') { [pscustomobject]@{EmailAddress = @{Address = $_ } } } }
                $PowerShellBody = [PSCustomObject]@{
                    message         = @{
                        subject      = $Title
                        body         = @{
                            contentType = "HTML"
                            content     = $HTMLcontent
                        }
                        toRecipients = @($Recipients)
                    }
                    saveToSentItems = "true"
                }

                $JSONBody = ConvertTo-Json -Compress -Depth 10 -InputObject $PowerShellBody
                New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/me/sendMail' -tenantid $env:TenantID -NoAuthCheck $true -type POST -body ($JSONBody)
            }
            Write-LogMessage -API 'Webhook Alerts' -message "Sent a webhook alert to email: $Title" -tenant $TenantFilter -sev info
   
        }
        catch {
            Write-Host "Could not send webhook alert to email: $($_.Exception.message)"
            Write-LogMessage -API 'Webhook Alerts' -message "Could not send webhook alerts to email. $($_.Exception.message)" -tenant $TenantFilter -sev info
        }

    }
    
    if ($Type -eq 'webhook') {
        Write-Host "Trying to send webhook"

        try {
            if ($Config.webhook -ne '') {
                switch -wildcard ($config.webhook) {

                    '*webhook.office.com*' {
                        $JSonBody = "{`"text`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. <br><br>$JSONContent`"}" 
                        Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                    }

                    '*discord.com*' {
                        $JSonBody = "{`"content`": `"You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. $JSONContent`"}" 
                        Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONBody
                    }
                    default {
                        Invoke-RestMethod -Uri $config.webhook -Method POST -ContentType 'Application/json' -Body $JSONContent
                    }
                }

            }
            Write-LogMessage -API 'Webhook Alerts' -message "Sent Webhook alert $title to External webhook" -tenant $TenantFilter -sev info

        }
        catch {
            Write-Host "Could not send alerts to webhook: $($_.Exception.message)"
            Write-LogMessage -API 'Webhook Alerts' -message "Could not send alerts to webhook: $($_.Exception.message)" -tenant $TenantFilter -sev info
        }
    }
    Write-Host "Trying to send to PSA"

    if ($Type -eq 'psa') {
        if ($config.sendtoIntegration) {
            try {

                $Alert = @{
                    TenantId   = $TenantFilter
                    AlertText  = "$HTMLContent"
                    AlertTitle = "$($Title)"
                }
                New-CippExtAlert -Alert $Alert
                Write-LogMessage -API 'Webhook Alerts' -tenant $TenantFilter -message "Sent PSA alert $title" -sev info

            }
            catch {
                Write-Host "Could not send alerts to ticketing system: $($_.Exception.message)"
                Write-LogMessage -API 'Webhook Alerts' -tenant $TenantFilter -message "Could not send alerts to ticketing system: $($_.Exception.message)" -sev info
            }
        }
    }
}


