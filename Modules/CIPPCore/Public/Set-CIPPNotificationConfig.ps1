function Set-CIPPNotificationConfig {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Wraps a webhook auth config value in a SecureString only to satisfy Set-CippKeyVaultSecret; the value is written to Azure Key Vault (encrypted at rest)')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '', Justification = 'webhookAuthUsername/webhookAuthPassword are stored config values for an outbound webhook integration, not interactive credentials')]
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
        [boolean]$UseStandardizedSchema
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
                $KeyVaultName = Get-CippKeyVaultName
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
