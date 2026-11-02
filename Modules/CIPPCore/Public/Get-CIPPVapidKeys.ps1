function Get-CIPPVapidKeys {
    <#
    .SYNOPSIS
        Return the instance's VAPID key pair for Web Push, generating it on first use.

    .DESCRIPTION
        The public key is not secret and lives in the Config table (InstanceProperties/VapidPublicKey)
        so the frontend can read it. The private key follows the notification-webhook secret pattern:
        Key Vault in production, the DevSecrets table on a local Azurite stack.

    .PARAMETER PublicOnly
        Skip the private key lookup. Used by the subscription list endpoint.

    .FUNCTIONALITY
        Internal
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Wraps the freshly generated private key in a SecureString only to satisfy Set-CippKeyVaultSecret; the value is written to Azure Key Vault (encrypted at rest)')]
    [CmdletBinding()]
    param([switch]$PublicOnly)

    $SecretName = 'CIPPVapidPrivateKey'
    $IsDev = $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true'

    $ConfigTable = Get-CIPPTable -tablename 'Config'
    $Public = (Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'VapidPublicKey'").Value

    if ([string]::IsNullOrWhiteSpace($Public)) {
        $Keys = [CIPP.WebPush]::GenerateVapidKeys()
        if ($IsDev) {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            Add-CIPPAzDataTableEntity @DevSecretsTable -Force -Entity @{
                PartitionKey = $SecretName
                RowKey       = $SecretName
                APIKey       = $Keys.PrivateKey
            } | Out-Null
        } else {
            Set-CippKeyVaultSecret -VaultName (Get-CippKeyVaultName) -Name $SecretName -SecretValue (ConvertTo-SecureString -AsPlainText -Force -String $Keys.PrivateKey) | Out-Null
        }
        Add-CIPPAzDataTableEntity @ConfigTable -Force -Entity @{
            PartitionKey = 'InstanceProperties'
            RowKey       = 'VapidPublicKey'
            Value        = $Keys.PublicKey
        } | Out-Null
        Write-LogMessage -API 'PushNotifications' -message 'Generated the VAPID key pair for Web Push notifications' -Sev 'Info'
        return @{ PublicKey = $Keys.PublicKey; PrivateKey = $Keys.PrivateKey }
    }

    if ($PublicOnly) { return @{ PublicKey = $Public } }

    $Private = if ($IsDev) {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq '$SecretName' and RowKey eq '$SecretName'").APIKey
    } else {
        Get-CippKeyVaultSecret -VaultName (Get-CippKeyVaultName) -Name $SecretName -AsPlainText
    }
    return @{ PublicKey = $Public; PrivateKey = $Private }
}
