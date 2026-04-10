
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
        $SchemaSource,
        $InvokingCommand,
        $Headers,
        $TableName,
        $RowKey = [string][guid]::NewGuid(),
        $Attachments,
        [switch]$UseStandardizedSchema
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

                # Add file attachments if provided
                if ($Attachments -and $Attachments.Count -gt 0) {
                    $PowerShellBody.message.attachments = @($Attachments | ForEach-Object {
                        @{
                            '@odata.type'  = '#microsoft.graph.fileAttachment'
                            name           = $_.Name
                            contentType    = $_.ContentType
                            contentBytes   = $_.ContentBytes
                        }
                    })
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

        $GetWebhookSecret = {
            param(
                [string]$SecretName
            )

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                return (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq '$SecretName' and RowKey eq '$SecretName'").APIKey
            }

            $KeyVaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            return (Get-CippKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText)
        }

        $RequestHeaders = @{}
        if ($Headers -is [hashtable]) {
            foreach ($HeaderName in $Headers.Keys) {
                $RequestHeaders[$HeaderName] = $Headers[$HeaderName]
            }
        }

        $WebhookAuthType = [string]$Config.webhookAuthType
        switch ($WebhookAuthType.ToLowerInvariant()) {
            'bearer' {
                $WebhookAuthToken = [string]$Config.webhookAuthToken
                if ($WebhookAuthToken -eq 'SentToKeyVault') {
                    $WebhookAuthToken = & $GetWebhookSecret -SecretName 'CIPPNotificationsWebhookAuthToken'
                }
                if (![string]::IsNullOrWhiteSpace($WebhookAuthToken)) {
                    $RequestHeaders['Authorization'] = "Bearer $WebhookAuthToken"
                }
            }
            'basic' {
                $WebhookAuthPassword = [string]$Config.webhookAuthPassword
                if ($WebhookAuthPassword -eq 'SentToKeyVault') {
                    $WebhookAuthPassword = & $GetWebhookSecret -SecretName 'CIPPNotificationsWebhookAuthPassword'
                }
                if (![string]::IsNullOrWhiteSpace($Config.webhookAuthUsername) -and ![string]::IsNullOrWhiteSpace($WebhookAuthPassword)) {
                    $BasicAuthBytes = [System.Text.Encoding]::UTF8.GetBytes("$($Config.webhookAuthUsername):$WebhookAuthPassword")
                    $RequestHeaders['Authorization'] = 'Basic {0}' -f [System.Convert]::ToBase64String($BasicAuthBytes)
                }
            }
            'apikey' {
                $WebhookAuthHeaderValue = [string]$Config.webhookAuthHeaderValue
                if ($WebhookAuthHeaderValue -eq 'SentToKeyVault') {
                    $WebhookAuthHeaderValue = & $GetWebhookSecret -SecretName 'CIPPNotificationsWebhookAuthHeaderValue'
                }
                if (![string]::IsNullOrWhiteSpace($Config.webhookAuthHeaderName) -and ![string]::IsNullOrWhiteSpace($WebhookAuthHeaderValue)) {
                    $RequestHeaders[$Config.webhookAuthHeaderName] = $WebhookAuthHeaderValue
                }
            }
            'customheaders' {
                $WebhookAuthHeaders = [string]$Config.webhookAuthHeaders
                if ($WebhookAuthHeaders -eq 'SentToKeyVault') {
                    $WebhookAuthHeaders = & $GetWebhookSecret -SecretName 'CIPPNotificationsWebhookAuthHeaders'
                }
                if (![string]::IsNullOrWhiteSpace($WebhookAuthHeaders)) {
                    try {
                        $CustomHeaders = $WebhookAuthHeaders | ConvertFrom-Json -AsHashtable
                        if ($CustomHeaders -is [hashtable]) {
                            foreach ($HeaderName in $CustomHeaders.Keys) {
                                if (![string]::IsNullOrWhiteSpace([string]$HeaderName)) {
                                    $RequestHeaders[[string]$HeaderName] = [string]$CustomHeaders[$HeaderName]
                                }
                            }
                        }
                    } catch {
                        Write-LogMessage -API 'Webhook Alerts' -message 'Webhook custom headers JSON is invalid. Continuing without custom auth headers.' -tenant $TenantFilter -sev warning
                    }
                }
            }
        }

        $ExtensionTable = Get-CIPPTable -TableName Extensionsconfig
        $ExtensionConfig = Get-CIPPAzDataTableEntity @ExtensionTable

        # Check if config exists and is not null before parsing
        if ($ExtensionConfig.config -and -not [string]::IsNullOrWhiteSpace($ExtensionConfig.config)) {
            $Configuration = $ExtensionConfig.config | ConvertFrom-Json
        } else {
            $Configuration = $null
        }

        if ($Configuration.CFZTNA.WebhookEnabled -eq $true -and $Configuration.CFZTNA.Enabled -eq $true) {
            $CFAPIKey = Get-ExtensionAPIKey -Extension 'CFZTNA'
            $RequestHeaders['CF-Access-Client-Id'] = $Configuration.CFZTNA.ClientId
            $RequestHeaders['CF-Access-Client-Secret'] = "$CFAPIKey"
            Write-Information 'CF-Access-Client-Id and CF-Access-Client-Secret headers added to webhook API request'
        }

        $UseStandardizedWebhookSchema = [boolean]$Config.UseStandardizedSchema
        if ($PSBoundParameters.ContainsKey('UseStandardizedSchema')) {
            $UseStandardizedWebhookSchema = [boolean]$UseStandardizedSchema
        }

        $EffectiveTitle = if ([string]::IsNullOrWhiteSpace($Title)) {
            '{0} - {1} - Webhook Alert' -f $APIName, $TenantFilter
        } else {
            $Title
        }

        $EffectiveSchemaSource = if (![string]::IsNullOrWhiteSpace($SchemaSource)) {
            $SchemaSource
        } elseif (![string]::IsNullOrWhiteSpace($APIName)) {
            $APIName
        } else {
            'CIPP'
        }

        $WebhookContent = if ($UseStandardizedWebhookSchema) {
            New-CIPPStandardizedWebhookSchema -Title $EffectiveTitle -TenantFilter $TenantFilter -Payload $JSONContent -Source $EffectiveSchemaSource -InvokingCommand $InvokingCommand
        } else {
            $JSONContent
        }

        if ($WebhookContent -isnot [string]) {
            $WebhookContent = $WebhookContent | ConvertTo-Json -Compress -Depth 50
        }

        $ReplacedContent = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $WebhookContent -EscapeForJson
        try {
            if (![string]::IsNullOrWhiteSpace($Config.webhook) -or ![string]::IsNullOrWhiteSpace($AltWebhook)) {
                $webhook = if ($AltWebhook) { $AltWebhook } else { $Config.webhook }
                if ($PSCmdlet.ShouldProcess($webhook, 'Sending webhook')) {
                    $RestMethod = @{
                        Uri                = $webhook
                        Method             = 'POST'
                        ContentType        = 'application/json'
                        StatusCodeVariable = 'WebhookStatusCode'
                        SkipHttpErrorCheck = $true
                    }
                    if ($RequestHeaders.Count -gt 0) {
                        $RestMethod['Headers'] = $RequestHeaders
                    }
                    switch -wildcard ($webhook) {
                        '*webhook.office.com*' {
                            if ($UseStandardizedWebhookSchema) {
                                $RestMethod['Body'] = $ReplacedContent
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            } else {
                                $TeamsBody = [PSCustomObject]@{
                                    text = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. <br><br>$ReplacedContent"
                                } | ConvertTo-Json -Compress
                                $RestMethod['Body'] = $TeamsBody
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            }
                        }
                        '*discord.com*' {
                            if ($UseStandardizedWebhookSchema) {
                                $RestMethod['Body'] = $ReplacedContent
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            } else {
                                $DiscordBody = [PSCustomObject]@{
                                    content = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. ``````$ReplacedContent``````"
                                } | ConvertTo-Json -Compress
                                $RestMethod['Body'] = $DiscordBody
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            }
                        }
                        '*slack.com*' {
                            if ($UseStandardizedWebhookSchema) {
                                $RestMethod['Body'] = $ReplacedContent
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            } else {
                                $SlackBlocks = Get-SlackAlertBlocks -JSONBody $JSONContent
                                if ($SlackBlocks.blocks) {
                                    $SlackBody = $SlackBlocks | ConvertTo-Json -Depth 10 -Compress
                                } else {
                                    $SlackBody = [PSCustomObject]@{
                                        text = "You've setup your alert policies to be alerted whenever specific events happen. We've found some of these events in the log. ``````$ReplacedContent``````"
                                    } | ConvertTo-Json -Compress
                                }
                                $RestMethod['Body'] = $SlackBody
                                $WebhookResponse = Invoke-RestMethod @RestMethod
                            }
                        }
                        default {
                            $RestMethod['Body'] = $ReplacedContent
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
