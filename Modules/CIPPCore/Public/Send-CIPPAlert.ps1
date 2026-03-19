
function Send-CIPPAlert {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $Type,
        $Title,
        $HTMLContent,
        $JSONContent,
        $TenantFilter,
        $altEmail,
        $altWebhook,
        $APIName = 'Send Alert',
        $Headers,
        $TableName,
        $RowKey = [string][guid]::NewGuid()
    )
    Write-Information 'Shipping Alert'
    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
    $Config = [pscustomobject](Get-CIPPAzDataTableEntity @Table -Filter $Filter)

    if ($HTMLContent) {
        $HTMLContent = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $HTMLContent
    }

    if ($Type -eq 'email') {
        Write-Information 'Trying to send email'
        try {
            if ($Config.email -like '*@*' -or $altEmail -like '*@*') {
                $Recipients = if ($AltEmail) {
                    [pscustomobject]@{EmailAddress = @{Address = $AltEmail } }
                } else {
                    $Config.email.split($(if ($Config.email -like '*,*') { ',' } else { ';' })).trim() | ForEach-Object {
                        if ($_ -like '*@*') {
                            ($Alias, $Domain) = $_ -split '@'
                            if ($Alias -match '%') {
                                # Allow for text replacement in alias portion of email address
                                $Alias = Get-CIPPTextReplacement -Text $Alias -Tenant $TenantFilter
                                $Recipient = "$Alias@$Domain"
                            } else {
                                $Recipient = $_
                            }
                            [pscustomobject]@{EmailAddress = @{Address = $Recipient } }
                        }
                    }
                }

                $PowerShellBody = [PSCustomObject]@{
                    message         = @{
                        subject      = $Title
                        body         = @{
                            contentType = 'HTML'
                            content     = $HTMLcontent
                        }
                        toRecipients = @($Recipients)
                    }
                    saveToSentItems = 'true'
                }

                $JSONBody = ConvertTo-Json -Compress -Depth 10 -InputObject $PowerShellBody

                if ($PSCmdlet.ShouldProcess($($Recipients.EmailAddress.Address -join ', '), 'Sending email')) {
                    $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/me/sendMail' -tenantid $env:TenantID -NoAuthCheck $true -type POST -body ($JSONBody)
                }

                $LogData = @{
                    Recipients = $Recipients
                }
                Write-LogMessage -API 'Webhook Alerts' -message "Sent an email alert: $Title" -tenant $TenantFilter -sev info -LogData $LogData
                return "Sent an email alert: $Title"
            }

        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Information "Could not send webhook alert to email: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -API 'Webhook Alerts' -message "Could not send webhook alerts to email. $($_.Exception.Message)" -tenant $TenantFilter -sev Error -LogData $ErrorMessage
            return "Could not send webhook alert to email: $($ErrorMessage.NormalizedError)"
        }
    }

    if ($Type -eq 'table' -and $TableName) {
        Write-Information 'Trying to send to Table'
        try {
            $Table = Get-CIPPTable -TableName $TableName
            $Alert = @{
                PartitionKey = $TenantFilter ?? 'Alert'
                RowKey       = $RowKey
                Title        = $Title
                Data         = [string]$JSONContent
                Tenant       = $TenantFilter
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Alert
            return $Alert.RowKey
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Information "Could not send alerts to table: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -API 'Webhook Alerts' -message "Could not send alerts to table: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -sev Error -LogData $ErrorMessage
        }
    }

    if ($Type -eq 'webhook') {
        Write-Information 'Trying to send webhook'

        $ExtensionTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @ExtensionTable).config | ConvertFrom-Json)

        if ($Configuration.CFZTNA.WebhookEnabled -eq $true -and $Configuration.CFZTNA.Enabled -eq $true) {
            $CFAPIKey = Get-ExtensionAPIKey -Extension 'CFZTNA'
            $Headers = @{'CF-Access-Client-Id' = $Configuration.CFZTNA.ClientId; 'CF-Access-Client-Secret' = "$CFAPIKey" }
            Write-Information 'CF-Access-Client-Id and CF-Access-Client-Secret headers added to webhook API request'
        } else {
            $Headers = $null
        }

        $ReplacedContent = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $JSONContent -EscapeForJson
        try {
            if (![string]::IsNullOrWhiteSpace($Config.webhook) -or ![string]::IsNullOrWhiteSpace($AltWebhook)) {
                if ($PSCmdlet.ShouldProcess($Config.webhook, 'Sending webhook')) {
                    $webhook = if ($AltWebhook) { $AltWebhook } else { $Config.webhook }
                    switch -wildcard ($webhook) {
                        '*webhook.office.com*' {
                            $TeamsBody = [PSCustomObject]@{
                                text = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. <br><br>$ReplacedContent"
                            } | ConvertTo-Json -Compress
                            $WebhookResponse = Invoke-RestMethod -Uri $webhook -Method POST -ContentType 'Application/json' -Body $TeamsBody -StatusCodeVariable WebhookStatusCode -SkipHttpErrorCheck
                        }
                        '*discord.com*' {
                            $DiscordBody = [PSCustomObject]@{
                                content = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. ``````$ReplacedContent``````"
                            } | ConvertTo-Json -Compress
                            $WebhookResponse = Invoke-RestMethod -Uri $webhook -Method POST -ContentType 'Application/json' -Body $DiscordBody -StatusCodeVariable WebhookStatusCode -SkipHttpErrorCheck
                        }
                        '*slack.com*' {
                            $SlackBlocks = Get-SlackAlertBlocks -JSONBody $JSONContent
                            if ($SlackBlocks.blocks) {
                                $SlackBody = $SlackBlocks | ConvertTo-Json -Depth 10 -Compress
                            } else {
                                $SlackBody = [PSCustomObject]@{
                                    text = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. ``````$ReplacedContent``````"
                                } | ConvertTo-Json -Compress
                            }
                            $WebhookResponse = Invoke-RestMethod -Uri $webhook -Method POST -ContentType 'Application/json' -Body $SlackBody -StatusCodeVariable WebhookStatusCode -SkipHttpErrorCheck
                        }
                        default {
                            $RestMethod = @{
                                Uri                = $webhook
                                Method             = 'POST'
                                ContentType        = 'application/json'
                                Body               = $ReplacedContent
                                StatusCodeVariable = 'WebhookStatusCode'
                                SkipHttpErrorCheck = $true
                            }
                            if ($Headers) {
                                $RestMethod['Headers'] = $Headers
                            }
                            $WebhookResponse = Invoke-RestMethod @RestMethod
                        }
                    }
                }
                $LogData = @{
                    WebhookUrl = $webhook
                    StatusCode = $WebhookStatusCode
                    Response   = $WebhookResponse
                }
                if ($WebhookStatusCode -ge 200 -and $WebhookStatusCode -lt 300) {
                    Write-LogMessage -API 'Webhook Alerts' -message "Sent Webhook alert $title to External webhook. Status code: $WebhookStatusCode" -tenant $TenantFilter -sev info -LogData $LogData
                    return "Sent webhook to $webhook with status code: $WebhookStatusCode"
                } else {
                    Write-LogMessage -API 'Webhook Alerts' -message "Webhook alert $title failed. $WebhookResponse" -tenant $TenantFilter -sev error -LogData $LogData
                    return "Error: Webhook returned status code $WebhookStatusCode for $webhook - Response: $WebhookResponse"
                }
            } else {
                Write-LogMessage -API 'Webhook Alerts' -message 'No webhook URL configured' -sev warning
            }

        } catch {
            $ErrorObject = Get-CippException -Exception $_
            $ErrorObject | Add-Member -NotePropertyName WebhookUrl -NotePropertyValue ($Config.webhook ?? $AltWebhook) -Force
            Write-Information "Could not send alerts to webhook: $($_.Exception.Message)"
            Write-LogMessage -API 'Webhook Alerts' -message "Could not send alerts to webhook: $($_.Exception.Message)" -tenant $TenantFilter -sev error -LogData $ErrorObject
            return "Error: Could not send alerts to webhook $($_.Exception.Message)"
        }
    }

    if ($Type -eq 'psa') {
        Write-Information 'Trying to send to PSA'
        if ($config.sendtoIntegration) {
            if ($PSCmdlet.ShouldProcess('PSA', 'Sending alert')) {
                try {
                    $Alert = @{
                        TenantId   = $TenantFilter
                        AlertText  = "$HTMLContent"
                        AlertTitle = "$($Title)"
                    }
                    New-CippExtAlert -Alert $Alert
                    Write-LogMessage -API 'Webhook Alerts' -tenant $TenantFilter -message "Sent PSA alert $title" -sev info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-Information "Could not send alerts to ticketing system: $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -API 'Webhook Alerts' -tenant $TenantFilter -message "Could not send alerts to ticketing system: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
        }
    }
}
