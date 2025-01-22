function Get-SherwebAuthentication {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Sherweb

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $APIKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Sherweb' and RowKey eq 'Sherweb'").APIKey
    } else {
        $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        $null = Connect-AzAccount -Identity
        $APIKey = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'sherweb' -AsPlainText)
    }
    $AuthBody = @{
        client_id     = $Config.clientId
        client_secret = $APIKey
        scope         = 'service-provider'
        grant_type    = 'client_credentials'
    }

    $Token = (Invoke-RestMethod -Uri 'https://api.sherweb.com/auth/oidc/connect/token' -Method POST -Body $AuthBody).access_token
    $authHeader = @{
        Authorization               = "Bearer $Token"
        'Ocp-Apim-Subscription-Key' = $Config.SubscriptionKey
    }

    return $authHeader
}
