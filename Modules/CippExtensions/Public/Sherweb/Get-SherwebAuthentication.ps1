function Get-SherwebAuthentication {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Sherweb
    $APIKey = Get-ExtensionAPIKey -Extension 'Sherweb'

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
