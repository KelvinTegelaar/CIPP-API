function Get-Pax8Authentication {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Pax8
    $APIKey = Get-ExtensionAPIKey -Extension 'Pax8'

    if ([string]::IsNullOrWhiteSpace($Config.clientId) -or [string]::IsNullOrWhiteSpace($APIKey)) {
        throw 'Pax8 Client ID or Client Secret is missing.'
    }

    $AuthBody = @{
        client_id     = $Config.clientId
        client_secret = $APIKey
        audience      = 'https://api.pax8.com'
        grant_type    = 'client_credentials'
    }

    $Token = (Invoke-RestMethod -Uri 'https://api.pax8.com/v1/token' -Method POST -Body $AuthBody).access_token
    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw 'Pax8 did not return an access token.'
    }

    return @{
        Authorization = "Bearer $Token"
    }
}
