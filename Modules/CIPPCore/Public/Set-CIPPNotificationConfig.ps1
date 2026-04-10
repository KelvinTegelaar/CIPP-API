function Set-CIPPNotificationConfig {
    [CmdletBinding()]
    param (
        $email,
        $webhook,
        $webhookAuthType,
        $webhookAuthToken,
        $webhookAuthUsername,
        $webhookAuthPassword,
        $webhookAuthHeaderName,
        $webhookAuthHeaderValue,
        $webhookAuthHeaders,
        $onepertenant,
        $logsToInclude,
        $sendtoIntegration,
        $sev,
        [boolean]$UseStandardizedSchema,
        $APIName = 'Set Notification Config'
    )

    try {
        $Table = Get-CIPPTable -TableName SchedulerConfig
        $ExistingConfig = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CippNotifications' and RowKey eq 'CippNotifications'"

        $StoreWebhookSecret = {
            param(
                [string]$SecretName,
                [string]$SecretValue
            )

            if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                $Secret = [PSCustomObject]@{
                    'PartitionKey' = $SecretName
                    'RowKey'       = $SecretName
                    'APIKey'       = $SecretValue
                }
                Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force | Out-Null
            } else {
                $KeyVaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
                Set-CippKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue (ConvertTo-SecureString -AsPlainText -Force -String $SecretValue) | Out-Null
            }
        }

        $WebhookSecretMap = @(
            @{ Field = 'webhookAuthToken'; SecretName = 'CIPPNotificationsWebhookAuthToken'; Value = [string]$webhookAuthToken }
            @{ Field = 'webhookAuthPassword'; SecretName = 'CIPPNotificationsWebhookAuthPassword'; Value = [string]$webhookAuthPassword }
            @{ Field = 'webhookAuthHeaderValue'; SecretName = 'CIPPNotificationsWebhookAuthHeaderValue'; Value = [string]$webhookAuthHeaderValue }
            @{ Field = 'webhookAuthHeaders'; SecretName = 'CIPPNotificationsWebhookAuthHeaders'; Value = [string]$webhookAuthHeaders }
        )

        $WebhookSecretMarkers = @{}
        foreach ($SecretInfo in $WebhookSecretMap) {
            $IncomingValue = [string]$SecretInfo.Value
            $ExistingValue = [string]$ExistingConfig.($SecretInfo.Field)

            if (![string]::IsNullOrWhiteSpace($IncomingValue) -and $IncomingValue -ne 'SentToKeyVault') {
                & $StoreWebhookSecret -SecretName $SecretInfo.SecretName -SecretValue $IncomingValue
                $WebhookSecretMarkers[$SecretInfo.Field] = 'SentToKeyVault'
            } elseif ($IncomingValue -eq 'SentToKeyVault' -or $ExistingValue -eq 'SentToKeyVault') {
                $WebhookSecretMarkers[$SecretInfo.Field] = 'SentToKeyVault'
            } else {
                $WebhookSecretMarkers[$SecretInfo.Field] = ''
            }
        }

        $SchedulerConfig = @{
            'tenant'                 = 'Any'
            'tenantid'               = 'TenantId'
            'type'                   = 'CIPPNotifications'
            'schedule'               = 'Every 15 minutes'
            'Severity'               = [string]$sev
            'email'                  = "$($email)"
            'webhook'                = "$($webhook)"
            'webhookAuthType'        = "$($webhookAuthType)"
            'webhookAuthToken'       = "$($WebhookSecretMarkers.webhookAuthToken)"
            'webhookAuthUsername'    = "$($webhookAuthUsername)"
            'webhookAuthPassword'    = "$($WebhookSecretMarkers.webhookAuthPassword)"
            'webhookAuthHeaderName'  = "$($webhookAuthHeaderName)"
            'webhookAuthHeaderValue' = "$($WebhookSecretMarkers.webhookAuthHeaderValue)"
            'webhookAuthHeaders'     = "$($WebhookSecretMarkers.webhookAuthHeaders)"
            'onePerTenant'           = [boolean]$onePerTenant
            'sendtoIntegration'      = [boolean]$sendtoIntegration
            'UseStandardizedSchema'  = [boolean]$UseStandardizedSchema
            'includeTenantId'        = $true
            'PartitionKey'           = 'CippNotifications'
            'RowKey'                 = 'CippNotifications'
        }
        foreach ($logvalue in [pscustomobject]$logsToInclude) {
            $SchedulerConfig[([pscustomobject]$logvalue.value)] = $true
        }

        Add-CIPPAzDataTableEntity @Table -Entity $SchedulerConfig -Force | Out-Null
        return 'Successfully set the configuration'
    } catch {
        return "Failed to set configuration: $($_.Exception.message)"
    }
}
